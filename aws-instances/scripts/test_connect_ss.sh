#!/bin/sh

set -e

HOSTNAME=${1:?Usage: test_connect_ss.sh <hostname>}

if ! nc -z -w 5 "$HOSTNAME" 443; then
    echo "ERROR: TCP 443 is not reachable on $HOSTNAME" >&2
    exit 1
fi

if nc -z -w 5 "$HOSTNAME" 22; then
    echo "ERROR: TCP 22 is unexpectedly reachable on $HOSTNAME" >&2
    exit 1
fi

echo "OK: TCP 443 is reachable and TCP 22 is inaccessible on $HOSTNAME"
