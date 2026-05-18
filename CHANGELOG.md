<!-- SPDX-License-Identifier: GPL-3.0-only -->

# pkg-framework changelog

All notable changes to the framework are recorded here. The framework
follows [semver](docs/versioning.md): breaking changes to the manifest
contract, the vendored-file layout, or the CLI subcommands bump the
major number.

## [Unreleased]

## [1.0.0] -- 2025-01-XX

Initial extraction. Folds vigil's and shroud's converged
`pkg/build.sh` (sections 1 through 14) and `.github/workflows/
pkg-build.yml` into a single source-of-truth library. Source repos
vendor the framework into `pkg/lib/` and declare a manifest in
`pkg/project.sh`.

### Added

- `lib/framework.sh` -- main bash library. Public entry point
  `run_pkg_build`; orchestrates env validation, dep install,
  toolchain, build, stage, fpm, reproducibility pass, manifest emit.
- `lib/layout-check.sh` -- post-install layout verification. Reads
  `PKG_BINARIES`, `PKG_SYSTEMD_UNITS`, `PKG_LAYOUT_CHECKS` and asserts
  the installed-tree shape. Calls
  `project_install_layout_check_extra` if defined.
- `lib/input-tests.sh` -- eight negative-case smoke tests against
  `pkg/build.sh`. Runs in workflow pre-flight.
- `lib/project.sh.example` -- annotated manifest template.
- `lib/build.sh.example` -- thin wrapper template.
- `lib/pkg-build.yml.tmpl` -- GitHub Actions workflow. Project-agnostic
  (reads `pkg/project.sh` at runtime). Four jobs: preflight, build
  matrix (deb on ubuntu/debian, rpm on fedora), install-test matrix,
  reproducibility (PR-only).
- `bin/pkg-framework` -- CLI with `version`, `new`, `sync`, `verify`
  subcommands.
- Manifest sidecar schema `pkg-framework-manifest/1`. Fields:
  `schema`, `framework_version`, `package`, `version`, `distro`,
  `artifact`, `sha256`, `size_bytes`, `source_commit`,
  `source_date_epoch`, `built_at`.
- 65-assertion bash test suite under `tests/unit/`. Covers helpers,
  manifest validation, env validation, manifest emit, layout check,
  and CLI subcommands.

### Contract

The 1.0.0 contract is locked. Future 1.x releases may add new
optional manifest fields and hook functions but must not break:

- The `pkg/project.sh` manifest schema (required scalars + arrays).
- The set of hook function names.
- The manifest sidecar JSON schema.
- The CLI subcommand surface.
- The vendored-file layout (`pkg/lib/{framework,layout-check,input-tests}.sh`
  plus `pkg/lib/VERSION` plus `.github/workflows/pkg-build.yml`).

Breaking changes ship in 2.0.0.
