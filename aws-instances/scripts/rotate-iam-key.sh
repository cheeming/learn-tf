#!/usr/bin/env bash
# Do not trace commands that handle credentials, even when invoked with bash -x.
set +xv
set -euo pipefail
umask 077
unset DEBUG GLAB_DEBUG GLAB_DEBUG_HTTP
export AWS_PAGER='' GLAB_CHECK_UPDATE=false

usage() {
    cat <<'USAGE'
Usage: rotate-iam-key.sh --user NAME --project ID_OR_PATH [options]

Delete the longest-unused eligible IAM key, create a replacement, and update
two existing GitLab project variables. Defaults to a read-only dry-run.

  --user NAME              IAM user name (required)
  --project ID_OR_PATH     GitLab numeric project ID or group/project (required)
  --days N                 Inactivity for previously used keys (default: 90; minimum: 1)
  --profile NAME           AWS CLI profile (otherwise use the normal AWS chain)
  --hostname HOST          GitLab host (default: gitlab.com)
  --scope SCOPE            Filter by exact environment scope (default: no filter)
  --id-variable NAME       Key ID variable (default: AWS_ACCESS_KEY_ID)
  --secret-variable NAME   Secret variable (default: AWS_SECRET_ACCESS_KEY)
  --apply                  Actually delete, create, and update
  --help                   Show this help

Never-used keys are eligible at any age and ranked by creation date. The key
authenticating this script is excluded, but an eligible key in GitLab CAN be deleted. Pause
pipelines and other consumers first: deletion is irreversible and the GitLab
updates are not atomic. Run only one rotation per IAM user/project at a time.
USAGE
}

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

user='' project='' days=90 profile='' hostname=gitlab.com scope=''
id_variable=AWS_ACCESS_KEY_ID secret_variable=AWS_SECRET_ACCESS_KEY apply=false
while (($#)); do
    case "$1" in
        --help) usage; exit 0 ;;
        --apply) apply=true; shift; continue ;;
        --user|--project|--days|--profile|--hostname|--scope|--id-variable|--secret-variable)
            if (($# < 2)) || [[ -z "$2" ]]; then
                die "Missing value for $1"
            fi
            case "$1" in
                --user) user=$2 ;; --project) project=$2 ;; --days) days=$2 ;;
                --profile) profile=$2 ;; --hostname) hostname=$2 ;; --scope) scope=$2 ;;
                --id-variable) id_variable=$2 ;; --secret-variable) secret_variable=$2 ;;
            esac
            shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done
[[ -n "$user" && -n "$project" ]] || die '--user and --project are required; see --help'
[[ "$user" =~ ^[A-Za-z0-9_+=,.@-]{1,64}$ ]] || die 'Invalid IAM user name'
[[ "$days" =~ ^[1-9][0-9]{0,5}$ ]] || die '--days must be an integer from 1 to 999999'
[[ "$id_variable" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && "$secret_variable" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 'Invalid variable name'
[[ "$id_variable" != "$secret_variable" ]] || die 'The two variable names must differ'
for dependency in aws glab jq date mktemp chmod rm; do
    command -v "$dependency" >/dev/null || die "Missing dependency: $dependency"
done
date -u -d '2000-01-01T00:00:00Z' +%s >/dev/null 2>&1 || die 'GNU-compatible date with -d is required'
aws_cli=(aws)
[[ -z "$profile" ]] || aws_cli+=(--profile "$profile")
aws_cli+=(--output json --no-cli-pager)

identity=$("${aws_cli[@]}" sts get-caller-identity) || die 'Cannot identify the AWS caller'
account=$(jq -er '.Account | select(type == "string" and length > 0)' <<<"$identity") || die 'Invalid AWS identity response'
caller=$(jq -er '.Arn' <<<"$identity") || die 'Missing AWS caller ARN'
# Export through the same provider chain; only retain the ID, never its secret.
auth_key=$("${aws_cli[@]}" configure export-credentials --format process 2>/dev/null |
    jq -er '.AccessKeyId | select(type == "string" and length > 0)') ||
    die 'Cannot resolve the caller access key; AWS CLI v2 with export-credentials is required'

encoded_project=$(printf '%s' "$project" | jq -sRr @uri)
id_endpoint="projects/$encoded_project/variables/$id_variable"
secret_endpoint="projects/$encoded_project/variables/$secret_variable"
if [[ -n "$scope" ]]; then
    encoded_scope=$(printf '%s' "$scope" | jq -sRr @uri)
    id_endpoint+="?filter%5Benvironment_scope%5D=$encoded_scope"
    secret_endpoint+="?filter%5Benvironment_scope%5D=$encoded_scope"
fi

get_variable() {
    local response validation
    if ! response=$(glab api "$1" --hostname "$hostname" --method GET 2>/dev/null); then
        printf 'GitLab API GET failed for %s on %s / %s. Check authentication, permissions, and variable existence; use --scope if the name exists in multiple scopes.\n' "$2" "$hostname" "$project" >&2
        return 1
    fi
    # Emit only fixed diagnostics; raw JSON and parser errors may contain secrets.
    if ! validation=$(printf '%s' "$response" | jq -ser --arg key "$2" --arg scope "$scope" '
        if length != 1 then "expected exactly one JSON value"
        else .[0] |
            if type != "object" then "response is not a JSON object"
            elif .key != $key then "key is missing or does not match the requested variable name"
            elif $scope != "" and .environment_scope != $scope then "environment_scope does not match --scope"
            elif .variable_type != "env_var" then "variable_type is missing or is not env_var (file variables are unsupported)"
            elif (has("value") | not) then "value is missing"
            elif (.value | type) != "string" and (.hidden != true or .value != null)
                then "value must be a string, or null with hidden: true"
            else "valid"
            end
        end' 2>/dev/null); then
        printf 'GitLab response validation failed for %s: invalid JSON or jq execution failure.\n' "$2" >&2
        return 1
    fi
    if [[ "$validation" != valid ]]; then
        printf 'GitLab response validation failed for %s: %s.\n' "$2" "$validation" >&2
        return 1
    fi
    printf '%s' "$response" | jq -cS .
}
old_id=$(get_variable "$id_endpoint" "$id_variable") || die "Cannot read existing env_var $id_variable (scope: ${scope:-unfiltered})"
old_secret=$(get_variable "$secret_endpoint" "$secret_variable") || die "Cannot read existing env_var $secret_variable (scope: ${scope:-unfiltered})"
current_key=$(jq -r '.value // empty' <<<"$old_id")
id_metadata=$(jq -cS 'del(.value)' <<<"$old_id")
secret_metadata=$(jq -cS 'del(.value)' <<<"$old_secret")

keys=$("${aws_cli[@]}" iam list-access-keys --user-name "$user") || die 'Cannot list IAM access keys'
jq -e '.AccessKeyMetadata | type == "array"' <<<"$keys" >/dev/null || die 'Invalid IAM key list'
jq -e 'all(.AccessKeyMetadata[];
    (.AccessKeyId | type == "string") and (.CreateDate | type == "string"))' <<<"$keys" >/dev/null || die 'Invalid IAM key metadata'
cutoff=$(($(date -u +%s) - days * 86400))
candidate='' candidate_time='' candidate_epoch=0
while IFS=$'\t' read -r key created; do
    [[ "$key" != "$auth_key" ]] || continue
    usage_json=$("${aws_cli[@]}" iam get-access-key-last-used --access-key-id "$key") || die "Cannot check last use of $key"
    last_used=$(jq -er '
        .AccessKeyLastUsed | select(type == "object") |
        if .LastUsedDate == null then ""
        else .LastUsedDate | select(type == "string" and length > 0)
        end' <<<"$usage_json") || die "Invalid last-use response for $key"
    last_epoch=$(date -u -d "${last_used:-$created}" +%s) || die "Invalid timestamp for $key"
    # Do not rank a key using a timestamp earlier than its creation.
    created_epoch=$(date -u -d "$created" +%s) || die "Invalid creation timestamp for $key"
    ((created_epoch > last_epoch)) && last_epoch=$created_epoch
    if { [[ -z "$last_used" ]] || ((last_epoch <= cutoff)); } &&
        { [[ -z "$candidate" ]] || ((last_epoch < candidate_epoch)); }; then
        candidate=$key candidate_time=${last_used:-"Never used (created $created)"} candidate_epoch=$last_epoch
    fi
done < <(jq -r '.AccessKeyMetadata[] | [.AccessKeyId, .CreateDate] | @tsv' <<<"$keys")
[[ -n "$candidate" ]] || die "No eligible key: keys must be never used or unused for at least $days days (the caller key is excluded); nothing changed"

printf 'AWS account: %s\nCaller: %s\nIAM user: %s\nSelected key: %s\nLast use: %s\n' \
    "$account" "$caller" "$user" "$candidate" "$candidate_time"
printf 'GitLab: %s / %s, scope %s\nVariables: %s, %s\n' "$hostname" "$project" "${scope:-unfiltered}" "$id_variable" "$secret_variable"
if [[ "$candidate" == "$current_key" ]]; then
    printf 'WARNING: This deletes the key currently configured in GitLab. Consumers may fail until rotation completes.\n' >&2
fi
if jq -e '.hidden == true and .value == null' <<<"$old_id" >/dev/null; then
    printf 'WARNING: The GitLab key ID is hidden; cannot determine whether the selected key is currently configured.\n' >&2
fi
if printf '%s\n%s\n' "$old_id" "$old_secret" | jq -se 'any(.[]; .hidden == true and .value == null)' >/dev/null; then
    printf 'WARNING: Hidden values cannot be read back or checked for concurrent value changes. Applying will retain a private recovery file for manual verification.\n' >&2
fi
if ! "$apply"; then
    printf 'Dry-run: no changes made. Pass --apply to delete this key and rotate credentials.\n'
    exit 0
fi

# Recheck immediately before deletion. This reduces races, but cannot prevent
# concurrent rotations or compensate for delayed IAM last-used reporting.
[[ "$(get_variable "$id_endpoint" "$id_variable")" == "$old_id" ]] || die 'GitLab ID variable changed or cannot be rechecked; retry'
[[ "$(get_variable "$secret_endpoint" "$secret_variable")" == "$old_secret" ]] || die 'GitLab secret variable changed or cannot be rechecked; retry'
rechecked_keys=$("${aws_cli[@]}" iam list-access-keys --user-name "$user") || die 'Cannot recheck IAM keys'
[[ "$(jq -cS '.AccessKeyMetadata | sort_by(.AccessKeyId)' <<<"$keys")" == \
   "$(jq -cS '.AccessKeyMetadata | sort_by(.AccessKeyId)' <<<"$rechecked_keys")" ]] || die 'IAM keys changed; retry'
rechecked_usage=$("${aws_cli[@]}" iam get-access-key-last-used --access-key-id "$candidate") || die 'Cannot recheck key usage'
rechecked_time=$(jq -er '
    .AccessKeyLastUsed | select(type == "object") |
    if .LastUsedDate == null then ""
    else .LastUsedDate | select(type == "string" and length > 0)
    end' <<<"$rechecked_usage") || die 'Invalid key usage recheck'
if [[ -n "$rechecked_time" ]]; then
    rechecked_epoch=$(date -u -d "$rechecked_time" +%s) || die 'Invalid timestamp in key usage recheck'
    ((rechecked_epoch <= cutoff)) || die 'Selected key was used recently; nothing changed'
fi
unset old_secret old_id

recovery_file=''
creation_attempted=false deleted=false completed=false
values_verified=true
id_updated=false secret_updated=false
cleanup() {
    local result=$?
    trap - EXIT
    if [[ -n "$recovery_file" ]]; then
        if ! "$creation_attempted" || { "$completed" && "$values_verified"; }; then
            rm -f -- "$recovery_file"
        elif "$completed"; then
            printf 'Private credential recovery file retained: %s\n' "$recovery_file" >&2
            printf 'Confirm the credentials work in GitLab before resuming normal pipelines, then remove this file. Hidden values were not read-back verified.\n' >&2
        else
            printf 'Rotation incomplete. Private credential recovery file: %s\n' "$recovery_file" >&2
            printf 'GitLab updates acknowledged: secret=%s, ID=%s. Verify both values before resuming pipelines.\n' "$secret_updated" "$id_updated" >&2
            printf 'Retain any newly created key for recovery. If the file is empty/incomplete, inspect IAM for an orphaned key.\n' >&2
        fi
    fi
    if "$deleted" && ! "$completed"; then
        printf 'The old key was deleted and cannot be restored.\n' >&2
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
recovery_file=$(mktemp "${TMPDIR:-/tmp}/rotate-iam-key.XXXXXXXX.json") || die 'Cannot allocate a private recovery file'
chmod 600 "$recovery_file" || die 'Cannot secure the recovery file'
"${aws_cli[@]}" iam delete-access-key --user-name "$user" --access-key-id "$candidate" >/dev/null || die 'Key deletion failed; verify IAM state before retrying'
deleted=true
creation_attempted=true
# Write the response directly to disk: the secret cannot be retrieved from IAM again.
"${aws_cli[@]}" iam create-access-key --user-name "$user" >"$recovery_file" 2>/dev/null || die 'Replacement creation failed; inspect the recovery file and IAM state'
jq -e --arg user "$user" '.AccessKey | .UserName == $user and
    (.AccessKeyId | type == "string" and length > 0) and
    (.SecretAccessKey | type == "string" and length > 0)' "$recovery_file" >/dev/null 2>&1 || die 'Invalid replacement response; recovery file retained'

# Read the value field from stdin without adding a newline or exposing it in argv.
# Leave protection, masking, visibility, raw, and scope unchanged.
jq -j '.AccessKey.SecretAccessKey' "$recovery_file" |
    glab api "$secret_endpoint" --hostname "$hostname" --method PUT --field value=@- --silent >/dev/null 2>&1 || die 'GitLab secret update failed'
secret_updated=true
jq -j '.AccessKey.AccessKeyId' "$recovery_file" |
    glab api "$id_endpoint" --hostname "$hostname" --method PUT --field value=@- --silent >/dev/null 2>&1 || die 'GitLab ID update failed'
id_updated=true
verify_variable() {
    local response
    response=$(get_variable "$1" "$2") || return 1
    [[ "$(jq -cS 'del(.value)' <<<"$response")" == "$4" ]] || {
        printf 'GitLab variable metadata changed unexpectedly for %s.\n' "$2" >&2
        return 1
    }
    if jq -e '.hidden == true and .value == null' <<<"$response" >/dev/null; then
        values_verified=false
        printf 'GitLab acknowledged the update to %s; metadata verified, hidden value cannot be read back.\n' "$2"
    else
        jq -e --arg field "$3" --slurpfile recovery "$recovery_file" \
            '.value == $recovery[0].AccessKey[$field]' <<<"$response" >/dev/null
    fi
}
verify_variable "$secret_endpoint" "$secret_variable" SecretAccessKey "$secret_metadata" || die 'GitLab secret verification failed'
verify_variable "$id_endpoint" "$id_variable" AccessKeyId "$id_metadata" || die 'GitLab ID verification failed'
completed=true
if "$values_verified"; then
    printf 'Rotation complete. Both GitLab variables verified; removing the temporary recovery file.\n'
else
    printf 'Rotation updates complete. Manual verification required for hidden values.\n'
fi
