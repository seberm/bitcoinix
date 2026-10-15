> [!NOTE]
> This documentation may be outdated. It is being updated.

This directory contains docs and helper scripts for developing and debugging:

- [`dev.sh`](./dev.sh): misc dev helpers
- [`dev-features.sh`](./dev-features.sh): helpers for developing specific
  nix-bitcoin features, like services
- [`topics`](./topics) features specific topics
- [`dev-scenarios.nix`](./dev-scenarios.nix): extra test scenarios used in the above scripts

See also: [test/README.md](../test/README.md)

## Run a dev shell

There are two ways to run a dev shell:

### 1. Run command `nix develop`

This starts a shell with [`test/run-tests.sh`](../test/run-tests.sh) and
the scripts in dir [`helper`](../helper) added to `PATH`.

### 2. Setup and start the `direnv` dev env

This is an opinionated, [direnv](https://direnv.net/)-based dev env, optimized for developer experience.

[`dev-env/create.sh`](./dev-env/create.sh) creates a git repo with the following contents:
- Dir `src` which contains the nix-bitcoin repo
- Dir `bin` for helper scripts
- File `scenarios.nix` for custom test scenarios
- File `.envrc` that defines a [direnv](https://direnv.net/) environment,
  mainly for adding nix-bitcoin and helper scripts to `PATH`

#### Installation

1. [Install direnv](https://direnv.net/docs/installation.html).\
   If you use NixOS (and Bash as the default shell), just add the following to your system config:
   ```nix
     environment.systemPackages = [ pkgs.direnv ];
     programs.bash.interactiveShellInit = ''
       eval "$(direnv hook bash)"
     '';
   ```

2. Create the dev env:
   ```bash
   # Set up a dev environment in dir ~/dev/nix-bitcoin.
   # The dir is created automatically.
   ./dev-env/create.sh ~/dev/nix-bitcoin

   cd ~/dev/nix-bitcoin

   # Enable direnv
   direnv allow
   ```

3. Optional: Editor integration
   - Add envrc support to your editor
   - Setup your editor so you can easily execute lines or paragraphs from a shell script
     file in a shell.\
     This simplifies using dev helper scripts like [`./dev.sh`](./dev.sh).

#### Explore the dev env
```bash
# The direnv is automatically activated when visiting any subdir of ~/dev/nix-bitcoin
cd ~/dev/nix-bitcoin

ls -al . bin lib

# The direnv config file
cat .envrc

# You can use this file to define extra scenarios
cat scenarios.nix

# Binary `dev-run-tests` runs nix-bitcoin's `run-tests.sh` with extra scenarios from ./scenarios.nix
# Example:
# Run command `nodeinfo` in `myscenario` (defined in ./scenarios.nix) via a container
dev-run-tests -s myscenario container --run c nodeinfo

# Equivalent (shorthand)
te -s myscenario container --run c nodeinfo

# Run the tests for `myscenario` in a VM
te -s myscenario

# Start an interactive shell inside a VM
te -s myscenario vm
```

See also: [test/README.md](../test/README.md)

## Adding a new service

It's easiest to use an existing service as a template:
- [electrs.nix](../modules/electrs.nix): a basic service
- [clightning.nix](../modules/clightning.nix): simple, but covers a few more features.\
  (A `cli` binary and a runtime-composed config to include secrets.)
- [rtl.nix](../modules/rtl.nix): includes a custom package, defined in [pkgs/rtl](../pkgs/rtl).\
  Most other services use packages that are already included in nixpkgs.

## Switching to a new NixOS release
- Run command `update-flake.sh 26.05`
- Treewide: check if any `TODO-EXTERNAL` comments can be resolved

## Cutting a release

A release is a signed, annotated git tag and nothing else. There are no release archives
and no GitHub release assets. Signing needs the maintainer's key, so this cannot run in CI.

```bash
helper/make-release.sh <version>    # e.g. 0.1.0, without the leading "v"
git push origin v<version>          # manual, the script never pushes
```

One-time setup:

```bash
git config gpg.format ssh
git config user.signingkey <path to your public key>
```

and your key must be listed in
[`helper/release-keys/ssh-allowed-signers`](../helper/release-keys/ssh-allowed-signers).

Before signing, the script checks that:
- you are on `master`, with no uncommitted changes to tracked files, and `HEAD` equals
  `origin/master`
- tag `v<version>` exists neither locally nor on `origin`
- `<version>` is a stable `X.Y.Z` that is greater than every existing release tag
- `gpg.format` is `ssh`, `user.signingkey` is set and the allowed signers file exists

It then creates the signed tag and verifies it with `helper/fetch-release.sh`, the same
check users run, against your local repository. If verification fails, it deletes the
tag it just created. Finally it prints the `git push` command, how to undo the tag
before pushing, and the post-release checks. Pass `-y` to skip the confirmation prompt.

After pushing, `checkDownload=1 version=<version> helper/fetch-release.sh` run from a clean
clone verifies the pushed tag and then downloads the archive that Nix users will get, into a
throwaway store and cache so that nothing local can satisfy it. It fails unless the archive
is exactly the signed tree. For a fork, also set `repoUrl=https://github.com/<owner>/<repo>`.

Tag names must match `^v[0-9]+(\.[0-9]+)*$`; `helper/fetch-release.sh` ignores anything else.
Pre-releases such as `0.1.0-rc1` are not supported.

The verification step is the one that matters: it fails if the tag was signed with a key
that is not listed in `ssh-allowed-signers`, which is the most likely way to publish an
unverifiable release. `.github/workflows/release.yml` repeats the same check after the
tag is pushed.

To add or retire a maintainer key, edit `helper/release-keys/ssh-allowed-signers` and
`SECURITY.md` together; `test/release-keys-test.sh` fails if the two drift apart. Retire a
key by appending `valid-before="YYYYMMDD"` to its line rather than deleting it, so that tags
signed while it was still valid keep verifying.
