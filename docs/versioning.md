<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Versioning policy

`pkg-framework` follows [Semantic Versioning 2.0.0](https://semver.org/).
The version lives in `pkg-framework/VERSION` (a single line of text)
and is independent of:

- `lousclues-pkg`'s own release cycle.
- Any source-project version (vigil, shroud, etc.).
- The `pkg-framework-manifest/N` sidecar schema version (which is
  separately versioned and only bumped on incompatible schema
  changes).

## What is covered

The semver contract covers the following surfaces. Breaking changes
to any of these require a major bump.

| Surface | Where it lives |
|---|---|
| Manifest schema (required and optional `PKG_*` variables) | `lib/project.sh.example`, [customization-surface.md](customization-surface.md) |
| Hook function names and signatures | [customization-surface.md](customization-surface.md) |
| Manifest sidecar JSON schema | The `schema` field in every `*.manifest.json`; today `pkg-framework-manifest/1` |
| CLI subcommand names and flags | `bin/pkg-framework` |
| Vendored-file layout in source repos | `pkg/lib/{framework,layout-check,input-tests}.sh`, `pkg/lib/VERSION`, `.github/workflows/pkg-build.yml` |
| Entry-point env contract | `DISTRO`, `VERSION`, `OUTDIR`, `${PKG_PREFIX}_MANIFEST_COMMIT` |
| Exit-code contract | `0` ok, `1` build / env error, `2` invalid input |

## What is NOT covered

These may change without a major bump:

- Internal function names (anything prefixed with `_pkg_`).
- The exact apt / dnf package list installed during dependency setup
  (additions are backward-compatible; removals are documented in the
  CHANGELOG but do not bump major).
- The output format of `log`, `section`, and other helpers.
- Container image versions in `pkg-build.yml` (rolled forward as
  upstream LTS lifecycles dictate).

## The sync contract

Every source project pins a framework version in `pkg/project.sh`:

```sh
FRAMEWORK_VERSION=1.0.0
```

This pin is enforced at three points:

1. **Runtime** (`_pkg_check_framework_version` in `framework.sh`):
   if the pin does not match the vendored `pkg/lib/VERSION`, the
   build aborts with a clear error.
2. **CI preflight** (`pkg-build.yml` preflight job): same check, run
   before the slow build matrix.
3. **`pkg-framework sync`**: refuses to overwrite vendored files if
   the pin in `pkg/project.sh` does not match the upstream
   `VERSION`, unless `--bump` is passed. With `--bump`, both the
   vendored files and the pin are updated atomically.

This three-fence design means a vendored copy can never silently drift
from the pin, and a pin can never silently drift from the vendored
copy. The only valid way to upgrade is `pkg-framework sync --bump`.

## When to sync

Source projects choose their cadence. Two reasonable policies:

- **Eager**: bump every patch release. Smallest diffs, lowest risk
  per bump, more PRs.
- **Lazy**: bump only on major releases or to pick up a specific
  feature. Larger diffs per bump, occasional bigger reviews.

The framework's `latest` line is announced in the
`lousclues-pkg/pkg-framework/CHANGELOG.md`. Subscribe to that file
via GitHub watch settings, or run `pkg-framework verify` periodically
in your local checkout to see drift against your dev-machine copy.

## Deprecation windows

Optional manifest fields and hooks scheduled for removal go through a
two-minor-release deprecation cycle:

1. Minor `1.N.0`: framework emits a deprecation warning when the
   field or hook is used. CHANGELOG announces the planned removal
   target (a future major).
2. Minor releases continue to honor the deprecated surface.
3. The next major `2.0.0` removes the surface.

Required fields and hooks cannot be deprecated; they can only be
removed in a major bump.

## Pre-1.0 status

The framework launched at 1.0.0. There is no 0.x history.

## Internal change cadence

`_pkg_*` functions, helper output formatting, and container image
versions roll on every release as needed. If a source project is
parsing `log` output or grepping `_pkg_*` symbol names, it is
relying on undocumented surface; please use the documented hooks
instead.
