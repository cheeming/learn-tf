#!/usr/bin/env bash
# TLS contents must never appear in shell traces or API debug output.
set +xv
set -euo pipefail
unset DEBUG GLAB_DEBUG GLAB_DEBUG_HTTP
export GLAB_CHECK_UPDATE=false

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }

project=tmpsc/learn-tf
hostname=gitlab.com
scope='*'
while (($#)); do
    case "$1" in
        --help)
            printf '%s\n' \
                'Usage: bash scripts/sync-ci-tls.sh [--project ID_OR_PATH] [--hostname HOST] [--scope SCOPE]' \
                'Sync local tmpsc_net.cer and tmpsc_net.key to protected GitLab File variables.' \
                'Defaults: project tmpsc/learn-tf, host gitlab.com, environment scope *.'
            exit 0 ;;
        --project|--hostname|--scope)
            if (($# < 2)) || [[ -z "$2" ]]; then
                die "Missing value for $1"
            fi
            case "$1" in
                --project) project=$2 ;;
                --hostname) hostname=$2 ;;
                --scope) scope=$2 ;;
            esac
            shift 2 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

for dependency in glab jq; do
    command -v "$dependency" >/dev/null || die "Missing dependency: $dependency"
done
module_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cert="$module_dir/files/tmpsc.net/tmpsc_net.cer"
key="$module_dir/files/tmpsc.net/tmpsc_net.key"
for file in "$cert" "$key"; do
    [[ -f "$file" && -r "$file" && -s "$file" ]] || die "Missing, unreadable or empty TLS file: $file"
done

encoded_project=$(printf '%s' "$project" | jq -sRr @uri)
encoded_scope=$(printf '%s' "$scope" | jq -sRr @uri)
endpoint="projects/$encoded_project/variables"
# List once to distinguish missing variables from API/authentication failures.
# Discard values immediately; GitLab includes secrets in the list response.
metadata=$(glab api "$endpoint?per_page=100" --hostname "$hostname" --paginate |
    jq -sc '[.[] | .[] | {key, environment_scope}]') || die 'Cannot list GitLab project variables'

sync_file() {
    local name=$1 file=$2 method=POST target="$endpoint"
    if jq -e --arg name "$name" --arg scope "$scope" \
        'any(.[]; .key == $name and .environment_scope == $scope)' <<<"$metadata" >/dev/null; then
        method=PUT
        target="$endpoint/$name?filter%5Benvironment_scope%5D=$encoded_scope"
    fi
    # glab reads the value from disk, keeping PEM contents out of process arguments.
    # Multiline PEM cannot be masked by GitLab; never print the API response.
    glab api "$target" --hostname "$hostname" --method "$method" --silent \
        --raw-field "key=$name" --field "value=@$file" \
        --raw-field variable_type=file --raw-field "environment_scope=$scope" \
        --field protected=true --field raw=true \
        >/dev/null 2>&1 || die "Cannot sync $name to $hostname/$project (scope: $scope)"
    printf 'Synced %s to %s/%s (scope: %s)\n' "$name" "$hostname" "$project" "$scope"
}

sync_file SS_TLS_CERT_FILE "$cert"
sync_file SS_TLS_KEY_FILE "$key"
