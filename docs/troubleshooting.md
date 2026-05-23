<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Troubleshooting pkg-framework

The top errors that hit a new project, with exact fixes.

## 1. `pkg-framework: framework VERSION not found at ... (use --framework-path)`

The CLI could not find its own `VERSION` file. Causes:

- You invoked `bin/pkg-framework` via a path that does not have a
  sibling `lib/` and `VERSION`. Fix: clone the framework somewhere
  stable and symlink the binary, do not copy just `bin/pkg-framework`.
- You set `PKG_FRAMEWORK_HOME` to the wrong directory. Fix: unset
  the variable or point it at the framework checkout root.

```sh
ls -1 "$PKG_FRAMEWORK_HOME"     # must show VERSION, bin/, lib/, ...
```

## 2. `pkg-framework: refuses to overwrite existing files in ...`

`pkg-framework new` is for fresh projects. If the target already has
`pkg/` or `.github/workflows/pkg-build.yml`, the CLI bails. Two
options:

- For a first conversion of an existing repo, move the conflicting
  paths aside and re-run `new`.
- For an existing pkg-framework project that needs updates, use
  `pkg-framework sync` (refresh vendored files only) or
  `pkg-framework upgrade` (bump the `FRAMEWORK_VERSION` pin too).

## 3. `pkg-framework: pinned FRAMEWORK_VERSION=... but upstream is ...`

The framework upstream has moved on from the version pinned in
`pkg/project.sh`. Two paths:

- Stay on the pinned version. Run `pkg-framework --framework-path
  /path/to/older-checkout sync` against an older checkout. The
  framework's versioning policy keeps the v1.x line backward-compatible.
- Adopt the new version. Run `pkg-framework upgrade`. Review the
  upstream `CHANGELOG.md` between your pinned version and the
  current one before committing.

## 4. `pkg-framework: DRIFT  pkg/lib/<file>`

`pkg-framework verify` found that a vendored file in the source repo
has drifted from upstream. Two possible causes:

- Someone edited the vendored file in place. Fix: revert the edit,
  then `pkg-framework sync`. If the edit was legitimately needed,
  upstream the change to `lousclues-labs/pkg-integration` instead.
- The upstream checkout has changed since the last sync. Fix:
  `pkg-framework upgrade` to acknowledge the new version.

## 5. The fpm build fails inside the workflow with `package <X> not found`

The framework runs `apt-get install` (deb) or `dnf install` (rpm) for
build-time deps before invoking cargo. If your project needs a system
header (e.g. `libssl-dev`), declare it as a build-time dep:

```sh
PKG_EXTRA_DEB_BUILD_DEPS=(libssl-dev)
PKG_EXTRA_RPM_BUILD_DEPS=(openssl-devel)
```

Run-time deps go in `PKG_DEB_DEPENDS` / `PKG_RPM_REQUIRES`; build-time
deps go in `PKG_EXTRA_*_BUILD_DEPS`. Mixing the two is the most common
mistake.

## 6. Post-install layout check fails: `missing: /usr/bin/<name>`

The cargo binary did not land where `PKG_LAYOUT_CHECKS` expects.
Causes:

- The binary name in `PKG_BINARIES` does not match the cargo `--bin`
  name in `Cargo.toml`. Fix: align them.
- The build produced multiple binaries but only the first is shipped.
  Fix: list every binary in `PKG_BINARIES`.

`pkg-framework dry-run` prints the resolved layout; diff it against
your expectation.

## 7. The manifest sidecar is missing or malformed

The framework emits `<artifact>.manifest.json` next to every deb /
rpm. The schema is `pkg-framework-manifest/1`. If a downstream
consumer (lousclues-pkg's `pkg-signing`, vigil's CI) reports
"schema mismatch", check:

- Your `FRAMEWORK_VERSION` pin matches your vendored framework.sh.
  Run `pkg-framework verify`. Drift on `framework.sh` can produce
  an old manifest schema.
- Nothing in `project_stage_extra` writes to the manifest path. The
  framework owns that sidecar; project hooks must not touch it.

## 8. fpm reports `Cannot package the path '...'` with multi-line description

Pre-v1.2.2 the framework passed common fpm args through a
newline-delimited string; a `PKG_DESCRIPTION` with literal newlines
spilled the second paragraph onto the fpm command line as a
positional path. Symptom:

```
Invalid package configuration: Cannot package the path
'/tmp/.../Second paragraph...', does it exist?
```

Fix: upgrade to v1.2.2+ and re-run `pkg-framework sync`. Multi-line
descriptions now survive intact into both deb and rpm metadata.

## 9. Build fails with `Broken pipe` on `dpkg-deb -c | head -20`

Pre-v1.2.2 the post-build validation piped the full listing through
`head -20`. Under `set -o pipefail`, packages with more than 20
entries trip a SIGPIPE on the producer and fail the whole build for
a perfectly valid artifact. Fix: upgrade to v1.2.2+.

## 10. Install-test in CI reports `/usr/share/doc/<name>/ missing`

Slim debian/ubuntu and minimal fedora base images drop docs and
man pages at install time:

- `/etc/dpkg/dpkg.cfg.d/excludes` strips `/usr/share/doc/*` and
  `/usr/share/man/*`.
- `/etc/dnf/dnf.conf` may have `tsflags=nodocs`.

v1.2.2 of the vendored `.github/workflows/pkg-build.yml` clears
both before installing the artifact, so the installed layout
matches the packaged layout. If you are still drifting after
upgrade, run `pkg-framework sync` and commit the result.

## 11. `pkg-framework version` fails through the installer symlink

Symptom: `~/.local/bin/pkg-framework version` exits with
`framework VERSION not found at .../local/VERSION`. Cause:
pre-v1.2.2 the CLI derived its home from `${BASH_SOURCE[0]}`
without resolving the symlink, landing at `~/.local` instead of
`~/.local/share/pkg-framework`. Fix: v1.2.2+ resolves the symlink
chain via `readlink -f` first.

## Getting help

If none of the above fits, file an issue on
`lousclues-labs/pkg-integration` with:

- `pkg-framework version` output
- `pkg-framework doctor` output
- `pkg-framework status` from the affected project
- the failing command's full stderr (with `--target` and
  `--framework-path` flags shown verbatim)
