<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Onboarding a new project to pkg-framework

Five minutes from a fresh Rust crate to signed deb + rpm artifacts on
every PR. Copy-paste your way through the steps.

## Prerequisites

One-line install (recommended):

```sh
curl -fsSL https://raw.githubusercontent.com/lousclues-labs/pkg-integration/main/install.sh | sh
```

The installer clones into `~/.local/share/pkg-framework`, symlinks
`~/.local/bin/pkg-framework`, and is idempotent (re-running upgrades).
To pin a specific version, set `PKG_FRAMEWORK_REF`:

```sh
PKG_FRAMEWORK_REF=v1.2.0 curl -fsSL https://raw.githubusercontent.com/lousclues-labs/pkg-integration/main/install.sh | sh
```

Manual install (if you prefer):

```sh
git clone git@github.com:lousclues-labs/pkg-integration.git \
    ~/.local/share/pkg-framework
ln -sf ~/.local/share/pkg-framework/bin/pkg-framework ~/.local/bin/
```

Confirm with:

```sh
pkg-framework version    # expect 1.2.0 or newer
pkg-framework doctor     # confirms bash 4+, sha256sum, awk, sed, install
```

If `pkg-framework doctor` reports any FAIL, install the named tool and
re-run. Doctor exits 0 only when every required tool is on PATH.

## Step 1: scaffold

From the root of the source repo (a Cargo project; the framework
assumes `cargo build --release --bin <name>` produces a single binary
per entry in `PKG_BINARIES`):

```sh
cd /path/to/my-rust-project
pkg-framework init       # interactive: autofills from Cargo.toml, git, LICENSE
```

`init` reads `Cargo.toml` (name, description, license), `git remote
get-url origin` (homepage + source URL), `LICENSE` (SPDX identifier),
and `git config user.name/user.email` (maintainer). It prompts only
for what cannot be detected. Add `--yes` to accept every detected
default without prompting (deterministic; used in CI).

For a non-interactive scaffold with no autofill, use the older verb:

```sh
pkg-framework new my-rust-project
```

What the scaffolder writes:

```
pkg/
  build.sh              # entry point. Two source lines + one call.
  project.sh            # the manifest. You edit this.
  lib/
    framework.sh        # vendored from upstream
    layout-check.sh     # vendored from upstream
    input-tests.sh      # vendored from upstream
    VERSION             # vendored from upstream
.github/workflows/
  pkg-build.yml         # vendored from upstream
```

The scaffolder refuses to overwrite anything. If it complains, use
`pkg-framework sync` instead (for an existing pkg-framework project)
or move the conflicting file aside.

## Step 2: edit `pkg/project.sh`

The file is data. Every `REQUIRED` field must be set. Most projects
change six things:

- `PKG_SUMMARY` and `PKG_DESCRIPTION` (one-line + multi-line)
- `PKG_MAINTAINER` and `PKG_HOMEPAGE_URL`
- `PKG_BINARIES` (the cargo `--bin` names to build)
- `PKG_DEB_DEPENDS` (debian dependency expressions)
- `PKG_LAYOUT_CHECKS` (path:mode pairs that fail closed if missing)
- `project_stage_extra()` (install configs, polkit, sudoers, systemd
  units)

See [customization-surface.md](customization-surface.md) for every
field and hook with concrete examples drawn from vigil and shroud.

## Step 3: lint and dry-run before committing

```sh
pkg-framework lint       # validates pkg/project.sh against the schema
pkg-framework dry-run    # prints the fpm command(s) it would invoke
```

`lint` catches missing required fields, malformed arrays, and bad
layout-check entries. Sub-second. Run it as often as you save the
manifest.

`dry-run` prints what `pkg/build.sh` would do without executing fpm.
Useful for reviewers: a packaging change shows up as a diff in the
dry-run output.

## Step 4: commit

```sh
git add pkg/ .github/workflows/pkg-build.yml
git commit -m 'pkg: adopt pkg-framework v1.1.0'
git push
```

The workflow runs on every PR. It builds deb + rpm in matrix
containers (Debian, Ubuntu, Fedora), runs the layout check inside
each installed distro, and emits the signed manifest sidecar.

## Step 5: keep the vendored copy honest

Two commands handle the maintenance side:

```sh
pkg-framework status     # one-liner: framework=X pinned=Y drift=N
pkg-framework verify     # detailed: every vendored file checked
```

`verify` is the CI drift gate. If anyone edits `pkg/lib/framework.sh`
by hand instead of upstreaming the change, CI fails with a clear
"DRIFT" diagnostic naming the file. To pick up a new upstream
release:

```sh
pkg-framework upgrade    # alias for `sync --bump`
pkg-framework verify     # confirm clean
```

## Common patterns

### Adding a systemd unit

1. Drop the unit file at `systemd/my-service.service` in the repo root.
2. In `pkg/project.sh`: `PKG_SYSTEMD_UNITS=(my-service.service)`.
3. The framework installs it to `/lib/systemd/system/` and runs
   `systemctl daemon-reload` in postinst automatically.

### Adding a config under /etc

1. In `pkg/project.sh`, implement `project_stage_extra`:
   ```sh
   project_stage_extra() {
       local root=$1
       install -D -m 0644 "$REPO_ROOT/config/my-service.conf" \
           "$root/etc/my-service/my-service.conf"
   }
   ```
2. Declare it as a deb conffile so apt prompts on change:
   `PKG_DEB_CONFIG_FILES=("/etc/my-service/my-service.conf")`.
3. Add the path to `PKG_LAYOUT_CHECKS=("etc/my-service/my-service.conf:644")`.

### Generating man pages from --help

```sh
project_post_build() {
    "$CARGO_TARGET_DIR/release/$PKG_NAME" gen-manpage \
        > "$STAGE/usr/share/man/man1/$PKG_NAME.1"
}
```

## When things go wrong

See [troubleshooting.md](troubleshooting.md). It lists the top five
errors with exact fixes.

## Bash completion

```sh
pkg-framework completion bash > ~/.local/share/bash-completion/completions/pkg-framework
```

Or source on the fly:

```sh
. <(pkg-framework completion bash)
```
