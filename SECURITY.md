# Security Policy

> [!NOTE]
> This is a basic draft. The project is a work in progress and this policy may change.

## Supported versions

Security fixes are provided on a best-effort basis for:

* the `master` branch
* the latest release tag

## Reporting a vulnerability

Please report vulnerabilities privately via
[GitHub private vulnerability reporting](https://github.com/bitcoinix/bitcoinix/security/advisories/new).

**Do not open a public issue or pull request for a vulnerability.**

Please include:

* a description of the vulnerability and its impact
* the affected module, package or file, and the revision (commit or release tag)
* the configuration needed to reproduce it
* steps to reproduce or a proof of concept
* a suggested fix, if you have one

## What to expect

bitcoinix is maintained by volunteers. Reports are handled on a best-effort basis,
without a guaranteed response time or fix time.

There is no security fund and no bug bounty (this may be reconsidered in the future).
The project relies on responsible reports and on the good faith of the community.
Reporters are credited in the [Wall of Fame](#wall-of-fame), unless they wish to remain anonymous.

Please follow [coordinated vulnerability disclosure](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure)
and give the maintainers a reasonable time to fix an issue before publishing it.

## Scope

In scope are bugs in the bitcoinix modules, packages and tooling in this repository,
including insecure defaults and documentation that suggests insecure practices.

Vulnerabilities in upstream dependencies (e.g. Bitcoin Core, Core Lightning, LND, nixpkgs)
should be reported to the respective upstream project first.

## Release signing

A bitcoinix release is a **signed, annotated git tag** (`v<version>`). There are no release
archives and no GitHub release assets. A tag that is not signed by one of the keys below
must not be trusted.

Releases are signed with SSH keys, not with GPG. The authoritative, machine-readable list is
[`helper/release-keys/ssh-allowed-signers`](helper/release-keys/ssh-allowed-signers);
the fingerprints below mirror it.

### Maintainer keys

**seberm** (GitHub: [seberm](https://github.com/seberm))

| Purpose | Type | Fingerprint |
| :-- | :-- | :-- |
| Release tags and commits | `sk-ecdsa-sha2-nistp256@openssh.com` | `SHA256:2o/0Op+64zKgF4oMaS0LGOiGPNDsibaqX6g8qMf5Hz0` |
| Offline rotation key | `ssh-ed25519` | `SHA256:BMLBnWuEhqLzNH+xUFRo0saOvOV/0ohz+OFqq93J+ec` |

### Verifying a release

In a clone of this repository:

```bash
git config gpg.ssh.allowedSignersFile helper/release-keys/ssh-allowed-signers
git tag -v v0.1.0
```

A good signature prints
`Good "git" signature for seberm@seberm.com with ECDSA-SK key SHA256:2o/0Op+...`.
The same setting makes `git log --show-signature` verify commits.

`helper/fetch-release.sh` performs this verification itself and refuses to emit a hash for an
unsigned tag, a lightweight tag, or a tag signed by a key that is not in the list.

Bootstrapping: the keys file lives in the repository it certifies, so it cannot vouch for
itself. The release tag key (`SHA256:2o/0Op+64zKgF4oMaS0LGOiGPNDsibaqX6g8qMf5Hz0`) is also
published outside this repository at <https://seberm.com/ssh.html> (source:
<https://github.com/seberm/seberm.com>), in a statement signed with seberm's GPG key
`0AF6 4C3B 1F12 14B3 8C8C  5786 1FA2 DBE6 7438 7CC3` (`0x1FA2DBE674387CC3`) and with the
SSH key itself. Verify that statement as described on that page and compare the
fingerprint with the table above. GitHub also independently marks tags and commits made
with these keys as *Verified*.

### Key rotation and compromise

Keys are never removed from `ssh-allowed-signers`. A retired key gets
`valid-before="YYYYMMDD"` instead, so that tags signed while it was still valid keep
verifying. A rotation is announced in a commit signed by the offline rotation key and in a
GitHub security advisory.

### Known limitation

Releases carry no signed "latest version" metadata. An attacker who can withhold tags can
keep a user on an older but validly signed release. Pass `version=` to `fetch-release` to
pin a release explicitly.

## Wall of Fame

These reports were handled by the upstream nix-bitcoin project.

| Researcher | Report | Fix | Reward | Payout transaction |
| :-- | :-- | :-- | :-- | :-- |
| [haoxucu](https://github.com/haoxucu) | `netns-exec` was executable by all normal users | [`34a18f92`](https://github.com/fort-nix/nix-bitcoin/commit/34a18f92eeacc754e5857249aaf8decf24e98cde) | 5% of the fund | [`5b93fbad…eb888`](https://mempool.space/tx/5b93fbad4b9a2c35daaf40b74fc76f0b69d2b75bc4da927cd3398dbc432eb888) |
| [haoxucu](https://github.com/haoxucu) | `lnd-create-macaroons` exposed the LND admin macaroon in `curl`'s process arguments | [`df184b6e`](https://github.com/fort-nix/nix-bitcoin/commit/df184b6e06cc3404add42ccf5ae68306395e8d6c) | 10% of the fund | [`5b93fbad…eb888`](https://mempool.space/tx/5b93fbad4b9a2c35daaf40b74fc76f0b69d2b75bc4da927cd3398dbc432eb888) |
| Mehdi Kerimov | `fetch-release` did not verify `nar-hash.txt` when `nar-hash.txt.asc` contained an inline signed message | [`da27f270`](https://github.com/fort-nix/nix-bitcoin/commit/da27f27026d92841e3ea91e100608ed9854ac013) | 15% of the fund | [`a0c5821e…83f3`](https://mempool.space/tx/a0c5821edcd45af98e5c0818560535a24c1a6dba29b5a4a05149ab1003c783f3) |

## Historical: upstream security fund

The upstream nix-bitcoin security fund is closed. Do not send donations to its former address.
The former policy is preserved in the upstream repository history and in the `forked` tag of this repository.
