<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Porting a project to pkg-framework

This guide walks through converting an existing source repository to
`pkg-framework`. It assumes the repo already has a working
`pkg/build.sh` and `.github/workflows/pkg-build.yml` (the converged
vigil / shroud baseline).

For a brand-new project, run `pkg-framework new <name>` instead;
this guide covers the retrofit path.

## Step 0: prerequisites

- `lousclues-pkg` checked out somewhere accessible.
- `bash`, `git`, `jq`, `shellcheck` installed locally.
- The source repo on a fresh branch, working tree clean.

## Step 1: scaffold the framework files

The first conversion uses `new` so we get the wrapper + example
manifest:

```sh
cd /path/to/source-repo
git checkout -b pkg-framework-adoption
# Move the existing pkg/build.sh out of the way temporarily.
mv pkg/build.sh pkg/build.sh.old
mv pkg/project.sh pkg/project.sh.old 2>/dev/null || true
mv .github/workflows/pkg-build.yml .github/workflows/pkg-build.yml.old

/path/to/lousclues-pkg/pkg-framework/bin/pkg-framework new <project-name>
```

The CLI writes:

```
pkg/build.sh              (thin wrapper; do not edit)
pkg/project.sh            (manifest; edit this)
pkg/lib/framework.sh      (vendored)
pkg/lib/layout-check.sh   (vendored)
pkg/lib/input-tests.sh    (vendored)
pkg/lib/VERSION           (vendored)
.github/workflows/pkg-build.yml  (vendored)
```

## Step 2: translate the old build.sh into the manifest

Open `pkg/project.sh` and your `pkg/build.sh.old` side by side. Walk
the old script section by section.

### Required scalars

Pulled from your old `fpm` invocation arguments and constants near
the top of the old `build.sh`:

| Manifest field | Old build.sh source |
|---|---|
| `PKG_NAME` | `--name` |
| `PKG_SUMMARY` | `--rpm-summary` and first line of description |
| `PKG_DESCRIPTION` | `--description` |
| `PKG_VENDOR` | `--vendor` |
| `PKG_MAINTAINER` | `--maintainer` |
| `PKG_HOMEPAGE_URL` | `--url` |
| `PKG_LICENSE_SPDX` | `--license` |
| `PKG_COPYRIGHT_HOLDERS` | debian/copyright generation block |
| `PKG_COPYRIGHT_YEAR` | debian/copyright generation block |
| `PKG_PREFIX` | the env-var prefix on `MANIFEST_COMMIT` (e.g. `VIGIL_MANIFEST_COMMIT` -> `VIGIL`) |

### Required arrays

| Manifest array | Old source |
|---|---|
| `PKG_BINARIES` | `cargo build --bin <name>` calls |
| `PKG_DEB_DEPENDS` | repeated `--depends ...` flags on the deb fpm invocation |

### Optional arrays (translate only what you used)

| Manifest array | Old source |
|---|---|
| `PKG_RPM_REQUIRES` | rpm fpm `--depends` (set only if it differs from deb) |
| `PKG_SYSTEMD_UNITS` | files staged into `$DEB_OUT/lib/systemd/system/` |
| `PKG_LAYOUT_CHECKS` | the old `validate_stage` and installed-layout `ok`/`fail` calls |
| `PKG_DEB_CONFIG_FILES` | `--config-files` on the deb fpm invocation |
| `PKG_EXTRA_DOC_FILES` | files staged under `usr/share/doc/<name>/` beyond README + CHANGELOG + copyright |

## Step 3: translate the project-specific bits into hooks

The hooks in `pkg/project.sh` are the customization surface. Map old
inline code to the appropriate hook.

| Old build.sh region | New hook |
|---|---|
| `stage_assets()` body beyond the canonical files | `project_stage_extra "$root"` |
| `emit_postinst()` body | `project_postinst_body` (output to stdout) |
| `emit_prerm()` / `emit_postrm()` | `project_prerm_body` / `project_postrm_body` |
| Pre-build code (generating man pages from binary, etc.) | `project_post_build` (runs after cargo build) |
| `validate_stage()` checks that can't be expressed as `path:mode` | `project_validate_stage_extra "$root"` |
| Workflow `verify installed layout` step that uses `getcap`, runtime smoke, etc. | `project_install_layout_check_extra` |

### Concrete example: vigil's setcap postinst

Vigil's old `emit_postinst` granted file caps. In the framework:

```sh
project_postinst_body() {
    cat <<'EOF'
# Grant net_admin + net_raw to vigild so it can manage routing tables
# without running as root.
if command -v setcap >/dev/null 2>&1; then
    setcap cap_net_admin,cap_net_raw+ep /usr/bin/vigild || true
fi
EOF
}

project_install_layout_check_extra() {
    if ! command -v getcap >/dev/null 2>&1; then
        return 0
    fi
    caps=$(getcap /usr/bin/vigild 2>/dev/null || true)
    case "$caps" in
        *cap_net_admin*cap_net_raw*) ;;
        *) printf 'getcap on /usr/bin/vigild did not report expected caps: %s\n' "$caps"; return 1 ;;
    esac
}
```

### Concrete example: shroud's sudoers + polkit

```sh
project_stage_extra() {
    local root=$1
    install -D -m 0440 "$REPO_ROOT/deploy/sudoers" \
        "$root/etc/sudoers.d/shroud"
    install -D -m 0644 "$REPO_ROOT/deploy/polkit-killswitch.policy" \
        "$root/usr/share/polkit-1/actions/com.shroud.killswitch.policy"
    install -D -m 0644 "$REPO_ROOT/deploy/shroud.desktop" \
        "$root/usr/share/applications/shroud.desktop"
}

project_postinst_body() {
    cat <<'EOF'
# Re-validate the sudoers fragment we just installed.
if command -v visudo >/dev/null 2>&1; then
    if ! visudo -cf /etc/sudoers.d/shroud >/dev/null 2>&1; then
        echo 'ERROR: /etc/sudoers.d/shroud failed visudo -cf' >&2
        rm -f /etc/sudoers.d/shroud
        exit 1
    fi
fi
# Refresh the desktop-file cache so the .desktop entry shows up.
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database -q /usr/share/applications || true
fi
EOF
}
```

## Step 4: validate locally

```sh
shellcheck --severity=warning pkg/build.sh pkg/lib/*.sh
bash -n pkg/build.sh pkg/lib/*.sh
( source pkg/project.sh; declare -p PKG_NAME PKG_BINARIES )

# Drift gate (should pass: we just synced).
/path/to/pkg-framework/bin/pkg-framework verify

# Input tests (no toolchain required).
bash pkg/lib/input-tests.sh
```

## Step 5: commit + push

```sh
rm pkg/build.sh.old pkg/project.sh.old .github/workflows/pkg-build.yml.old
git add pkg/ .github/workflows/pkg-build.yml
git commit -m 'pkg: adopt pkg-framework v1.0.0'
git push -u origin pkg-framework-adoption
```

The first CI run on the branch exercises the full preflight + build +
install-test + reproducibility matrix. Compare the output artifact's
sha256 against the previous main-branch build to confirm parity. If
the sha256 differs, run `diffoscope old.deb new.deb` to find the
divergence; expected differences are limited to the new manifest
sidecar (which is a separate file, not part of the deb).

## Step 6: keeping the framework in sync over time

Whenever upstream `pkg-framework` releases a new version:

```sh
cd source-repo
git checkout -b pkg-framework-bump-1.X.Y
/path/to/pkg-framework/bin/pkg-framework sync --bump
git diff pkg/lib/ .github/workflows/pkg-build.yml
git commit -am 'pkg: bump pkg-framework to 1.X.Y'
git push -u origin pkg-framework-bump-1.X.Y
```

The drift gate in CI catches manual edits to vendored files. Any
project-specific behavior change must go through `pkg/project.sh`
(data or hooks).
