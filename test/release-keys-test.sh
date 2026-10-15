#!/usr/bin/env bash
# Checks helper/release-keys/ssh-allowed-signers: every key line must be a valid
# ssh public key, and its fingerprint must be documented in SECURITY.md so that
# the two cannot drift apart.
set -euo pipefail

scriptDir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
signers=$scriptDir/../helper/release-keys/ssh-allowed-signers
policy=$scriptDir/../SECURITY.md

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

failures=0
fail() { printf 'FAIL   %s\n' "$1"; failures=$((failures + 1)); }

# Some OpenSSH versions (e.g. on the CI runner) warn "missing key" on empty lines
if blank=$(grep -n '^[[:space:]]*$' "$signers"); then
    fail "empty line(s) in the allowed signers file, use a bare '#' instead: ${blank//$'\n'/, }"
fi

keys=0
while read -r principal options keytype keydata; do
    [[ $principal && ${principal:0:1} != "#" ]] || continue
    keys=$((keys + 1))
    label="$principal $keytype"

    if [[ ! $keydata ]]; then
        fail "$label: line has no options field; expected 'principal options keytype keydata'"
        continue
    fi

    printf '%s %s\n' "$keytype" "$keydata" > "$tmp/key.pub"
    if ! fingerprint=$(ssh-keygen -lf "$tmp/key.pub" 2>/dev/null | awk '{print $2}'); then
        fail "$label: not a valid ssh public key"
        continue
    fi

    before=$failures

    # Releases are git object signatures only
    if [[ $options != *'namespaces="git"'* ]]; then
        fail "$label: missing namespaces=\"git\" restriction"
    fi

    if ! grep -qF "$fingerprint" "$policy"; then
        fail "$label: fingerprint $fingerprint is not documented in SECURITY.md"
    fi

    ((failures > before)) || printf 'ok     %s %s\n' "$label" "$fingerprint"
done < "$signers"

if ((keys == 0)); then
    fail "no keys found in $signers"
fi

echo
if ((failures)); then
    echo "$failures check(s) failed"
    exit 1
fi
echo "All release key checks passed ($keys key(s))"
