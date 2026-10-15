#!/usr/bin/env nix-shell
#!nix-shell -i bash -p bash coreutils git gnutar gnugrep gnused openssh
set -euo pipefail

# Print a `builtins.fetchTarball` expression for a bitcoinix release, after
# verifying that the release tag is signed by a maintainer key listed in
# helper/release-keys/ssh-allowed-signers.
#
# A release is a signed, annotated git tag and nothing else. The hash is computed
# from the verified git objects, not from a downloaded archive, so the printed
# expression pins the exact tree that was signed.
#
# Env vars (for forks and tests):
#   version         release version without the leading "v" (default: highest release tag)
#   repoUrl         git repository to fetch from
#   allowedSigners  path to the allowed signers file
#   checkDownload   if set, also download the printed url and check that it serves the
#                   verified tree. Needs network access and takes a few seconds more.

scriptDir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)

trap 'echo "Error at ${BASH_SOURCE[0]}:$LINENO"' ERR

repoUrl=${repoUrl:-https://github.com/bitcoinix/bitcoinix}
allowedSigners=${allowedSigners:-$scriptDir/release-keys/ssh-allowed-signers}

die() { >&2 printf 'Error: %s\n' "$@"; exit 1; }

[[ -f $allowedSigners ]] || die "No allowed signers file at $allowedSigners"

# `version` is interpolated into a Nix expression and a ref name, so constrain it
versionRegex='^[0-9]+(\.[0-9]+)*$'

if [[ -v version && $version ]]; then
    [[ $version =~ $versionRegex ]] || die "Invalid version: '$version'"
else
    # Use the tags themselves, not the GitHub `releases/latest` API: that API is
    # unsigned, mutable metadata, so a compromised account could use it to steer
    # users to an older signed release.
    version=$(git ls-remote --tags --refs "$repoUrl" 'v*' \
              | sed -nE 's|.*[[:space:]]refs/tags/v([0-9]+(\.[0-9]+)*)$|\1|p' \
              | sort -V | tail -1)
    [[ $version ]] || die "No release tags found at $repoUrl"
fi
tag=v$version

tmp=$(mktemp -d)
# Nix store paths are read-only, which `rm -rf` cannot remove
trap 'chmod -R u+w "$tmp" 2>/dev/null; rm -rf "$tmp"' EXIT
repo=$tmp/repo
tree=$tmp/tree
mkdir -p "$tree"

# Fetch only the release tag
git init -q --bare "$repo"
git -C "$repo" fetch -q --depth 1 "$repoUrl" "+refs/tags/$tag:refs/tags/$tag" ||
    die "No tag $tag at $repoUrl"

# Verify the tag with the trusted keys only. The invoking user's git config is
# ignored here so that neither their allowed signers file nor their GPG keyring
# can widen the trust set.
verify() {
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
        git -C "$repo" -c gpg.ssh.allowedSignersFile="$allowedSigners" "$@"
}

# Must be an annotated tag object, not a lightweight tag
[[ $(git -C "$repo" cat-file -t "refs/tags/$tag") == tag ]] ||
    die "$tag is not an annotated tag object"

tagObject=$(git -C "$repo" cat-file tag "refs/tags/$tag")
# Headers only, i.e. up to the first empty line
tagHeaders=$(sed -n '/^$/q;p' <<<"$tagObject")

# The signed tag object carries its own name and target type. Checking them blocks
# replaying an older, validly signed tag object under a newer ref name (rollback).
[[ $(sed -nE 's/^tag (.*)$/\1/p' <<<"$tagHeaders" | head -1) == "$tag" ]] ||
    die "Tag object name does not match ref $tag"
[[ $(sed -nE 's/^type (.*)$/\1/p' <<<"$tagHeaders" | head -1) == commit ]] ||
    die "Tag $tag does not point to a commit"

# Releases are SSH-signed. git verify-tag detects the signature type from the
# payload, so without this check a GPG-signed tag could be accepted via the
# invoking user's keyring.
grep -q '^-----BEGIN SSH SIGNATURE-----' <<<"$tagObject" ||
    die "Tag $tag does not carry an SSH signature"

if ! verify verify-tag "$tag" >/dev/null 2>"$tmp/verify.log"; then
    >&2 echo "Error: signature verification failed for tag $tag of $repoUrl"
    >&2 echo "Only keys in $allowedSigners are trusted."
    >&2 sed 's/^/  /' "$tmp/verify.log"
    exit 1
fi
>&2 grep -E '^Good' "$tmp/verify.log" || true

commit=$(git -C "$repo" rev-parse "refs/tags/$tag^{commit}")

# Hash the verified git objects. This repository has no .gitattributes, so
# GitHub's archive of the same commit has identical content and `fetchTarball`
# computes the same NAR hash, which makes Nix enforce the verified tree.
git -C "$repo" archive --format=tar "$commit" | tar -x -C "$tree"
hash=$(nix-hash --type sha256 --sri "$tree")

>&2 echo "Fetched and verified release $version ($commit)"

# The url is pinned to the commit, not to the mutable tag name, so moving or
# deleting the tag later cannot change what this expression resolves to.
url=$repoUrl/archive/$commit.tar.gz
expression=$(cat <<EOF
builtins.fetchTarball {
  url = "$url";
  sha256 = "$hash";
}
EOF
)

if [[ ${checkDownload:-} ]]; then
    # The hash above comes from git objects, so check that the url really serves that
    # tree. Nix skips the download if the hash is already in its store or in its
    # fetcher cache, so evaluate in a throwaway store and cache, without binary caches.
    # `pwd -P`: Nix rejects a store below a symlink (e.g. /var on macOS).
    check=$(mkdir "$tmp/check" && cd "$tmp/check" && pwd -P)
    mkdir "$check/store" "$check/cache"
    if ! XDG_CACHE_HOME=$check/cache nix-instantiate --eval --store "$check/store" \
            --option substituters '' -E "$expression" >/dev/null 2>"$tmp/check.log"; then
        >&2 sed 's/^/  /' "$tmp/check.log"
        die "Could not fetch $url as the verified tree"
    fi
    >&2 echo "Downloaded $url, it matches the verified tree"
fi

echo "$expression"
