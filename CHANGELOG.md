<!-- SPDX-License-Identifier: GPL-3.0-only -->

# pkg-framework changelog

All notable changes to the framework are recorded here. The framework
follows [semver](docs/versioning.md): breaking changes to the manifest
contract, the vendored-file layout, or the CLI subcommands bump the
major number.

## [Unreleased]

## [1.2.0] - 2026-05-23

Tier 3 from the post-split plan. Reduces the onboarding loop from
"edit 12 fields in pkg/project.sh" to "answer 5 prompts (or pass
--yes)." Adds a one-liner installer and an automated release
pipeline so downstream consumers can pin to a release URL with a
published sha256.

### Added

- `bin/pkg-framework init [<name>] [--yes]`. Interactive scaffold.
  Reads `Cargo.toml` (name, description, license), `git remote
  get-url origin` (homepage + source URL), `LICENSE` (SPDX), and
  `git config user.name/email` (maintainer) to pre-fill the
  manifest. Prompts only for what cannot be detected.  `--yes`
  accepts every detected default without prompting (CI-friendly).
- `bin/pkg-framework status --json`. Machine-readable envelope:
  `{schema, framework, pinned, drift, drifted_files}`.
  Schema `pkg-framework-status/1`. Useful for status checks in
  consumer CI without parsing the human one-liner.
- `install.sh`. POSIX-sh one-liner installer. Clones into
  `~/.local/share/pkg-framework`, symlinks the cli into
  `~/.local/bin`, and is idempotent for re-runs. Pins via
  `PKG_FRAMEWORK_REF=v1.2.0` env var.
- `.github/workflows/release.yml`. Triggered on `v*` tag push.
  Builds a deterministic tarball (sorted, owner=0, mtime from the
  tagged commit's `SOURCE_DATE_EPOCH`), computes its sha256,
  extracts the matching `CHANGELOG.md` section, and creates a
  GitHub Release with everything attached. Consumers can pin to
  the release URL.
- Smoke test extended with three new steps (10, 11, 12) covering
  `status --json` (envelope shape + jq parse), `init --yes` end
  to end (autofills + lints clean), and `install.sh` syntax
  validation under `/bin/sh`. Total: 32 checks across 12 steps.

### Changed

- `docs/onboarding.md` now leads with the one-liner installer and
  `pkg-framework init`. `new` remains documented as the
  non-interactive fallback.
- Bash completion includes `init` and offers `--yes`.

## [1.1.0] - 2026-05-23

Onboarding-focused release. CI is wired, a smoke test proves the
scaffold-verify-drift-sync round trip end to end, the CLI gains
five new subcommands meant to shorten the new-project loop, and
there are two new docs (`onboarding.md`, `troubleshooting.md`)
that complement the reference README.

### Added

- `bin/pkg-framework doctor`. Environment preflight. Reports
  required tools (bash 4+, sha256sum, awk, sed, install, grep,
  find, tr) plus optional build-time tools (cargo, fpm,
  docker/podman, dnf/apt-get). First command a new operator
  runs. Exit 0 only when every required tool is on PATH.
- `bin/pkg-framework lint`. Validates `pkg/project.sh` against
  the manifest schema without building. Checks required scalars
  and arrays, debian-naming for `PKG_NAME`, uppercase + underscore
  for `PKG_PREFIX`, `path:NNN` shape for `PKG_LAYOUT_CHECKS`.
  Sub-second feedback.
- `bin/pkg-framework dry-run`. Prints the fpm commands and
  staging plan without executing fpm. Reviewer-friendly: a
  packaging change shows up as a diff in `dry-run` output.
- `bin/pkg-framework status`. One-liner:
  `framework=X pinned=Y drift=N`. Useful for status badges and
  inline CI checks. Exits non-zero when drift > 0 or pin
  mismatch.
- `bin/pkg-framework upgrade`. Alias for `sync --bump`. Better
  verb for the common case.
- `bin/pkg-framework completion bash`. Emits a tab completion
  script.
- `.github/workflows/ci.yml`. Four jobs (lint, test, bash4,
  smoke) that gate every PR. Lint runs shellcheck (warning
  severity), an em-dash voice gate, and basic markdown link
  sanity. The bash4 job runs the unit suite inside a `bash:4.4`
  container to catch portability drift.
- `Makefile`. `make help`, `make test`, `make smoke`,
  `make lint{,-shell,-voice,-docs}`, `make ci`, `make doctor`.
  Mirrors CI locally so contributors prove the gate before push.
- `tests/smoke/test_onboard_new_project.sh`. End-to-end:
  scaffold a throwaway project -> verify (must pass) ->
  introduce drift in a vendored file -> verify (must fail and
  name the file) -> sync -> verify (must pass again) -> status
  (drift=0) -> lint (clean) -> dry-run (mentions project).
  24 checks total. Pinned by `make smoke`.
- `docs/onboarding.md`. Single-page copy-pasteable walkthrough
  from clone to first signed deb + rpm. Five steps plus three
  common patterns (systemd unit, /etc config, man pages from
  --help).
- `docs/troubleshooting.md`. Top seven errors with exact fixes.

### Changed

- `bin/pkg-framework` accepts global flags
  (`--framework-path`, `--target`) both BEFORE and AFTER the
  subcommand. Previously the flags had to follow the
  subcommand; now either order works. Subcommand-first remains
  the documented form.
- DRY: extracted `_pinned_framework_version` helper. `sync`,
  `verify`, and `status` all read the `FRAMEWORK_VERSION` pin
  through the same function. Reduces three identical `awk`
  expressions to one.

### Fixed

- Em-dash gate Makefile target previously used a byte-class
  regex (`[\xe2\x80\x94]`) that matched any one of those three
  bytes individually instead of the three-byte UTF-8 sequence.
  Now uses `grep -F (literal em-dash)` against the literal codepoint.

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
