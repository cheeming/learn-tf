#!/bin/sh

set -e

HOSTNAME=${1:?Usage: test_connect_ss.sh <hostname> [reachable|blocked]}
EXPECTED_HTTPS=${2:-reachable}

case "$EXPECTED_HTTPS" in
    reachable|blocked) ;;
    *)
        echo "ERROR: Expected TCP 443 status must be reachable or blocked" >&2
        exit 2
        ;;
esac

command -v nc >/dev/null 2>&1 || {
    echo "ERROR: nc is required for connectivity checks" >&2
    exit 1
}

case "$EXPECTED_HTTPS" in
    reachable)
        if ! nc -z -w 5 "$HOSTNAME" 443; then
            echo "ERROR: TCP 443 is not reachable on $HOSTNAME" >&2
            exit 1
        fi
        ;;
    blocked)
        if nc -z -w 5 "$HOSTNAME" 443; then
            echo "ERROR: TCP 443 is unexpectedly reachable on $HOSTNAME" >&2
            exit 1
        fi
        ;;
esac

if nc -z -w 5 "$HOSTNAME" 22; then
    echo "ERROR: TCP 22 is unexpectedly reachable on $HOSTNAME" >&2
    exit 1
fi

echo "OK: TCP 443 is $EXPECTED_HTTPS and TCP 22 is inaccessible on $HOSTNAME"
