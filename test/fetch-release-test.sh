#!/usr/bin/env bash
# Offline tests for helper/fetch-release.sh.
#
# Uses throwaway ssh keys and a local repository served via file://, so no
# network access and no maintainer key are needed. Run directly or via
# `nix shell nixpkgs#{git,openssh,gnutar}`.
set -euo pipefail

scriptDir=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
fetchRelease=$scriptDir/../helper/fetch-release.sh

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Isolate from the developer's git config: a global commit.gpgsign or signingkey
# would make the fixture commits try to use a real maintainer key.
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_CONFIG_GLOBAL=$tmp/gitconfig
cat > "$GIT_CONFIG_GLOBAL" <<EOF
[user]
    name = bitcoinix test
    email = test@example.com
[commit]
    gpgsign = false
[tag]
    gpgsign = false
    forceSignAnnotated = false
[gpg]
    format = ssh
[init]
    defaultBranch = master
EOF

failures=0
pass() { printf 'ok     %s\n' "$1"; }
fail() { printf 'FAIL   %s\n' "$1"; failures=$((failures + 1)); }

mkkey() { ssh-keygen -q -t ed25519 -N '' -C "$1" -f "$tmp/$1"; }
mkkey trusted-a
mkkey trusted-b
mkkey untrusted

signers=$tmp/allowed_signers
{
    printf 'a@example.com namespaces="git" %s\n' "$(cat "$tmp/trusted-a.pub")"
    printf 'b@example.com namespaces="git" %s\n' "$(cat "$tmp/trusted-b.pub")"
} > "$signers"

# A source repository with one commit, re-created for each scenario
src=$tmp/src
new_repo() {
    rm -rf "$src"
    git init -q "$src"
    echo content > "$src/file"
    git -C "$src" add file
    git -C "$src" commit -q -m "initial commit"
}

# Add a commit, so that tags created before and after it point at different trees
add_commit() {
    echo "$1" > "$src/file"
    git -C "$src" commit -q -a -m "$1"
}

# sign_tag <name> <keyname>
sign_tag() {
    git -C "$src" -c user.signingkey="$tmp/$2.pub" tag -s "$1" -m "release $1"
}

# serve_archive <tag> [extra file]: publish an archive of the tag's commit at the url that
# fetch-release prints for repoUrl=file://$src. Like GitHub's it has one top-level
# directory, which fetchTarball strips. An extra file makes it differ from the signed tree.
serve_archive() {
    local commit stage=$tmp/stage
    commit=$(git -C "$src" rev-parse "$1^{commit}")
    rm -rf "$stage"; mkdir -p "$stage" "$src/archive"
    git -C "$src" archive --format=tar --prefix=repo/ "$commit" | tar -x -C "$stage"
    if [[ ${2:-} ]]; then echo tampered > "$stage/repo/$2"; fi
    tar -czf "$src/archive/$commit.tar.gz" -C "$stage" repo
}

# run_fetch [env assignments...] -> captures stdout in $out, stderr in $err
run_fetch() {
    out=$tmp/stdout; err=$tmp/stderr
    env repoUrl="file://$src" allowedSigners="$signers" "$@" \
        bash "$fetchRelease" >"$out" 2>"$err"
}

#――― must pass ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――

new_repo
sign_tag v0.1.0 trusted-a
if run_fetch && grep -q 'builtins.fetchTarball' "$tmp/stdout" &&
   grep -q 'sha256 = "sha256-' "$tmp/stdout"; then
    pass "tag signed by a trusted key"
else
    fail "tag signed by a trusted key"; sed 's/^/       /' "$tmp/stderr"
fi

# The printed url must pin the commit, not the tag name
commit=$(git -C "$src" rev-parse 'v0.1.0^{commit}')
if grep -q "archive/$commit.tar.gz" "$tmp/stdout"; then
    pass "url is pinned to the commit"
else
    fail "url is pinned to the commit"
fi

# The hash must equal the NAR hash of the tree the tag points at
expected=$(cd "$tmp" && rm -rf t && mkdir t &&
           git -C "$src" archive --format=tar "$commit" | tar -x -C t &&
           nix-hash --type sha256 --sri t)
if grep -qF "$expected" "$tmp/stdout"; then
    pass "hash matches the signed tree"
else
    fail "hash matches the signed tree (expected $expected)"
fi

# The tags point at different commits, so the commit in the output identifies the tag
new_repo
sign_tag v0.1.0 trusted-a
add_commit second
sign_tag v0.2.0 trusted-a
if run_fetch version=0.1.0 && grep -q "$(git -C "$src" rev-parse 'v0.1.0^{commit}')" "$tmp/stdout"; then
    pass "explicit version= overrides tag selection"
else
    fail "explicit version= overrides tag selection"; sed 's/^/       /' "$tmp/stderr"
fi

# v0.10.0 sorts before v0.9.0 as a string
new_repo
sign_tag v0.9.0 trusted-a
add_commit second
sign_tag v0.10.0 trusted-a
if run_fetch && grep -q "$(git -C "$src" rev-parse 'v0.10.0^{commit}')" "$tmp/stdout"; then
    pass "highest version is chosen by version order, not string order"
else
    fail "highest version is chosen by version order, not string order"; sed 's/^/       /' "$tmp/stderr"
fi

new_repo
sign_tag v0.1.0 trusted-b
if run_fetch; then
    pass "tag signed by a second trusted key (multi-maintainer)"
else
    fail "tag signed by a second trusted key (multi-maintainer)"; sed 's/^/       /' "$tmp/stderr"
fi

# Without checkDownload the archive is never fetched, so it does not have to exist
new_repo
sign_tag v0.1.0 trusted-a
if run_fetch && [[ ! -e $src/archive ]]; then
    pass "download is not checked by default"
else
    fail "download is not checked by default"
fi

new_repo
sign_tag v0.1.0 trusted-a
serve_archive v0.1.0
if run_fetch checkDownload=1 && grep -q 'builtins.fetchTarball' "$tmp/stdout"; then
    pass "checkDownload accepts an archive that matches the signed tree"
else
    fail "checkDownload accepts an archive that matches the signed tree"; sed 's/^/       /' "$tmp/stderr"
fi

#――― must fail ―――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――

# expect_failure <description> <pattern expected in stderr>
expect_failure() {
    if run_fetch "${@:3}"; then
        fail "$1 (accepted)"
    elif grep -qi "$2" "$tmp/stderr"; then
        pass "$1"
    else
        fail "$1 (rejected, but not for the expected reason)"
        sed 's/^/       /' "$tmp/stderr"
    fi
}

new_repo
git -C "$src" tag -a v0.1.0 -m "release v0.1.0"
expect_failure "unsigned annotated tag" "SSH signature"

new_repo
git -C "$src" tag v0.1.0
expect_failure "lightweight tag" "annotated tag object"

new_repo
sign_tag v0.1.0 untrusted
expect_failure "tag signed by an untrusted key" "verification failed"

# Rollback replay: a validly signed tag object re-pointed at a newer ref name
new_repo
sign_tag v0.1.0 trusted-a
git -C "$src" update-ref refs/tags/v0.2.0 "$(git -C "$src" rev-parse refs/tags/v0.1.0)"
expect_failure "validly signed tag object replayed under another ref name" "does not match ref"
expect_failure "replayed tag object is also rejected when pinned via version=" "does not match ref" version=0.2.0

# No silent fallback to an older, properly signed tag
new_repo
sign_tag v0.1.0 trusted-a
git -C "$src" tag -a v0.3.0 -m "release v0.3.0"
expect_failure "unsigned newest tag does not fall back to an older signed tag" "SSH signature"

new_repo
sign_tag v0.1.0 trusted-a
expect_failure "version containing shell metacharacters" "invalid version" "version=0.1.0; id"
expect_failure "version containing a path traversal" "invalid version" "version=../../etc"

# The tag is fine, but the url does not serve what was signed
new_repo
sign_tag v0.1.0 trusted-a
expect_failure "checkDownload with an archive that cannot be fetched" "verified tree" checkDownload=1

new_repo
sign_tag v0.1.0 trusted-a
serve_archive v0.1.0 evil-file
expect_failure "checkDownload with an archive that differs from the signed tree" "hash mismatch" checkDownload=1

# A key retired with valid-before must not certify a later tag
new_repo
sign_tag v0.1.0 trusted-a
printf 'a@example.com namespaces="git",valid-before="20200101" %s\n' "$(cat "$tmp/trusted-a.pub")" > "$signers"
expect_failure "key retired via valid-before" "verification failed"
printf 'a@example.com namespaces="git" %s\n' "$(cat "$tmp/trusted-a.pub")" > "$signers"

# A signature made in another namespace must not count as a git signature
new_repo
sign_tag v0.1.0 trusted-a
printf 'a@example.com namespaces="file" %s\n' "$(cat "$tmp/trusted-a.pub")" > "$signers"
expect_failure "key restricted to another namespace" "verification failed"

echo
if ((failures)); then
    echo "$failures test(s) failed"
    exit 1
fi
echo "All fetch-release tests passed"
