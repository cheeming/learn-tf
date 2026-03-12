#!/bin/bash

_DIRNAME=$(dirname "${0}")
_FILES="${_DIRNAME}/../files"

echo ""
echo "Current tmpsc.net cert and keys..."
md5sum ${_FILES}/tmpsc.net/tmpsc_net.*

echo ""
echo "The current dates for cert:"
~/src/Scripts/check-cert-date.sh ${_FILES}/tmpsc.net/tmpsc_net.cer

echo ""
echo "New tmpsc.net cert and keys..."
md5sum "${HOME}/.acme.sh/tmpsc.net/fullchain.cer" "${HOME}/.acme.sh/tmpsc.net/tmpsc.net.key"

echo ""
echo "The new dates for cert:"
~/src/Scripts/check-cert-date.sh ~/.acme.sh/tmpsc.net/fullchain.cer

echo ""
echo "Copy new files..."
cp "${HOME}/.acme.sh/tmpsc.net/fullchain.cer" "${_FILES}/tmpsc.net/tmpsc_net.cer"
cp "${HOME}/.acme.sh/tmpsc.net/tmpsc.net.key" "${_FILES}/tmpsc.net/tmpsc_net.key"
