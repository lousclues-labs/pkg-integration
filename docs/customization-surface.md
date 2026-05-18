<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Customization surface

Every project-specific behavior is reached through `pkg/project.sh`.
This file is sourced before `pkg/lib/framework.sh` and declares two
kinds of data: variables (scalars and arrays) and hook functions.

If you find yourself wanting to edit a vendored file, the drift gate
will catch it. Add a hook or open a framework PR instead.

## Required scalars

| Name | Type | Notes |
|---|---|---|
| `PKG_NAME` | string | Lowercase alnum + hyphen. Debian package-name rules. |
| `PKG_PREFIX` | string | Uppercase alnum + underscore. Used for `${PREFIX}_MANIFEST_COMMIT` env var. |
| `PKG_SUMMARY` | string | One-line description. Maps to rpm `Summary:` and deb first synopsis line. |
| `PKG_DESCRIPTION` | string | Multi-line description (newlines preserved). |
| `PKG_VENDOR` | string | fpm `--vendor`. |
| `PKG_MAINTAINER` | `Name <email>` | deb `Maintainer:` and debian/copyright `Upstream-Contact`. |
| `PKG_HOMEPAGE_URL` | URL | deb `URL:`. |
| `PKG_SOURCE_URL` | URL | debian/copyright `Source:`. |
| `PKG_LICENSE_SPDX` | string | fpm `--license`. SPDX expression. |
| `PKG_LICENSE_NAME` | string | Human-readable name for debian/copyright. |
| `PKG_COPYRIGHT_HOLDERS` | string | debian/copyright `Files: *` stanza. |
| `PKG_COPYRIGHT_YEAR` | string | Year or range, e.g. `2024-2025`. |

## Required arrays

| Name | Notes |
|---|---|
| `PKG_BINARIES` | Cargo `--bin` names. Each is built and installed to `/usr/bin/<name>`. |
| `PKG_DEB_DEPENDS` | Each entry is one full debian Depends expression (version qualifiers OK). |

## Optional scalars

| Name | Default | Notes |
|---|---|---|
| `FRAMEWORK_VERSION` | unpinned | Set by `pkg-framework sync`. Mismatch with vendored `pkg/lib/VERSION` is a hard error. |
| `FPM_VERSION` | `1.16.0` | fpm gem version pin. |
| `SOURCE_DATE_EPOCH_DEFAULT` | `1700000000` | Reproducibility epoch. |
| `PKG_DEB_SECTION` | `net` | debian Section. |
| `PKG_DEB_PRIORITY` | `optional` | debian Priority. |
| `PKG_RPM_GROUP` | `Applications/System` | rpm Group. |
| `PKG_CARGO_FEATURES` | unset | If set, build uses `--no-default-features --features "$PKG_CARGO_FEATURES"`. |

## Optional arrays

| Name | Notes |
|---|---|
| `PKG_RPM_REQUIRES` | rpm Requires. If unset, derived from `PKG_DEB_DEPENDS` by stripping version qualifiers. |
| `PKG_LAYOUT_CHECKS` | `path:mode` tuples (mode optional). Walked by both pre-fpm `_pkg_validate_stage` and post-install `layout-check.sh`. |
| `PKG_SYSTEMD_UNITS` | Filenames under `<repo>/systemd/`. Staged to `/lib/systemd/system/`. `daemon-reload` is appended to postinst when non-empty. |
| `PKG_DEB_CONFIG_FILES` | Paths marked as deb conffiles. |
| `PKG_DEB_CONFLICTS`, `PKG_DEB_REPLACES`, `PKG_RPM_CONFLICTS` | Standard fpm fields. |
| `PKG_EXTRA_DOC_FILES` | Repo-relative paths shipped under `/usr/share/doc/<name>/`. |
| `PKG_EXTRA_DEB_BUILD_DEPS`, `PKG_EXTRA_RPM_BUILD_DEPS` | Build-time apt / dnf packages added to the framework's base list. |

## Hook functions

All hooks are optional. The framework checks `declare -F <name>`
before calling. Hooks see all `PKG_*` variables plus `REPO_ROOT`,
`STAGE`, `DEB_OUT`, `RPM_OUT`, `DISTRO`, `VERSION`, `OUTDIR`,
`CARGO_TARGET_DIR`, `SOURCE_DATE_EPOCH`.

### Dependency phase

| Hook | When | Use |
|---|---|---|
| `project_pre_install_deb_deps` | Before `apt-get install` | Add apt repos, accept license prompts. |
| `project_post_install_deb_deps` | After `apt-get install` | Post-dep setup. |
| `project_pre_install_rpm_deps` / `project_post_install_rpm_deps` | rpm equivalents. | |

### Build phase

| Hook | When | Use |
|---|---|---|
| `project_pre_build` | Before `cargo build` | Generate vendored sources, fetch deps. |
| `project_post_build` | After `cargo build` (binaries stripped) | Invoke the just-built binary to generate man pages, completions, etc. Outputs land in any path; usually `$STAGE/...` |

### Stage phase

| Hook | When | Use |
|---|---|---|
| `project_stage_extra <root>` | After framework stages binaries + docs + systemd units. `$1` is the install root (`$DEB_OUT` or `$RPM_OUT`). | Install configs, polkit, sudoers, apt/dnf package-manager hooks, autostart entries. |
| `project_postinst_body` | Before fpm reads the postinst script. Output to stdout. | The framework wraps your output with `#!/bin/sh`, `set -e`, and `exit 0`. |
| `project_prerm_body` / `project_postrm_body` | Same wrapping. | Service stop / cleanup. |

### Validation phase

| Hook | When | Use |
|---|---|---|
| `project_validate_stage_extra <root>` | After framework's pre-fpm checks. Return non-zero to abort. | Assertions not expressible as `path:mode`. |
| `project_install_layout_check_extra` | Inside the install-test job, in the distro container, after the package is installed. Return non-zero to fail. | Runtime smoke, `getcap`, `getent`, version assertions beyond what the framework checks. |

### fpm extension

| Hook | Use |
|---|---|
| `project_fpm_deb_extra_args` | Print extra fpm flags for deb, one per line. |
| `project_fpm_rpm_extra_args` | Same for rpm. |

Use these sparingly. Most customization should flow through the
typed `PKG_*` fields above; raw fpm flags are an escape hatch for
behavior not yet covered by the manifest.

## Worked examples

See [porting-guide.md](porting-guide.md) for vigil (setcap + man
pages) and shroud (sudoers + polkit + .desktop) cases.

## Asking for new surface

If your project needs a hook or field that does not exist, file an
issue against `lousclues-pkg` describing the use case. Adding a new
optional field or hook is a minor-version bump; removing or renaming
one is a major. The framework grows by collecting common patterns,
not by absorbing project-specific code.
