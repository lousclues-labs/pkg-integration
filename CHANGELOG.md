<!-- SPDX-License-Identifier: GPL-3.0-only -->

# pkg-framework changelog

All notable changes to the framework are recorded here. The framework
follows [semver](docs/versioning.md): breaking changes to the manifest
contract, the vendored-file layout, or the CLI subcommands bump the
major number.

## [Unreleased]

## [1.3.0] - 2026-05-24

Minor bump because the on-disk install layout and the env-var
surface changed. Consumer projects (vigil, shroud, the other repos
that vendor pkg-framework) see no manifest or CLI contract change
and require no action. Operators who curl|bash the installer get a
new directory shape and a new env var the first time they upgrade,
and `pkg-framework` resolves through it transparently.

### Added

- **`COPYRIGHT`** (A5). Project preamble plus a five-line pointer
  to `LICENSE`. Separates the optional notices the project chooses
  to publish (copyright statement, trademark disclaimer) from the
  GPL-3.0 text itself.
- **`tests/README.md`** (A7). Documents the harness contract, the
  `_assert.sh` helper namespace, the unit-vs-smoke boundary, and
  how to add a test.
- **`tests/_TEMPLATE.sh`** (A7). Runnable skeleton an operator can
  copy into `tests/unit/test_<name>.sh` and fill in. Exercises one
  call of each assertion helper so the template doubles as a smoke
  check for the helpers themselves.

### Changed

- **`install.sh`** (A1). Fresh installs now land at
  `$PKG_FRAMEWORK_ROOT/versions/<id>/` and a `current` symlink
  retargets to the newest version. Atomic swap is done with a temp
  symlink plus `mv -f` (`rename(2)` on symlinks is atomic; the same
  guarantee does NOT hold for non-empty directories, so the previous
  `mv -fT` approach was unsound). Effects:
  - Re-install cannot leave a half-extracted tree visible to a
    concurrent `pkg-framework` invocation.
  - Rollback is one symlink retarget; old versions remain in
    `versions/<old-id>/` until pruned.
  - New env var `PKG_FRAMEWORK_ROOT` (default
    `${XDG_DATA_HOME:-$HOME/.local/share}/pkg-framework`). The
    previous `PKG_FRAMEWORK_HOME` is honored as a deprecated alias
    and emits a one-line deprecation notice.
  - New env var `PKG_FRAMEWORK_KEEP` (default `2`) caps retained
    old versions; older ones are pruned after a successful retarget.
  - First run after upgrading detects the pre-v1.2.5 flat layout
    and renames it to `$ROOT.legacy.<epoch>` rather than mutating
    it in place. No data is removed.
  - `bin/pkg-framework` is unchanged: it resolves its own real path
    via `readlink -f` and derives `FRAMEWORK_HOME` from there, so
    the `current` symlink is transparent to the CLI.
- **`LICENSE`** (A5). Now contains only the verbatim GPL-3.0 text.
  The project preamble moved to `COPYRIGHT`. This is what
  GitHub's license detector expects; the previous file was not
  recognized because the GPL header was not the first content.
- **`SECURITY.md`** (A6). The PGP-key URL claim was removed. The
  page never went live, and a security contact must not advertise
  infrastructure it does not operate. Key exchange happens out of
  band on first contact; reporters who need
  encryption-in-transit should say so in their first email.
- **`Makefile`** (A3). `lint-voice` no longer relies on
  `grep -q` in an `if !` (which trips the `pipefail` + SIGPIPE
  trap). It checks for matching files first, prints the offending
  lines on stderr if any, then exits non-zero. `VOICE_FILES` now
  covers `COPYRIGHT`, `SECURITY.md`, and every `tests/*.md`.
  `SHELL_FILES` adds `install.sh` and `tests/_TEMPLATE.sh` so the
  shellcheck gate covers them.
- **`.github/workflows/release.yml`**. The release tarball
  invocation now includes `COPYRIGHT` and `SECURITY.md` alongside
  `LICENSE`, `README.md`, `CHANGELOG.md`, and `VERSION`.

### Hardened

Late review of the install.sh rewrite caught three edges. Folded
into this same minor because the install.sh surface is new with
v1.3.0 and shipping the rewrite without these would just queue up a
v1.3.1.

- **`migrate_legacy_layout` positive-marker guard.** The old
  detection treated "ROOT exists, no `current` symlink, no
  `versions/`" as proof of a legacy install. That false-positives
  on a hand-mkdir'd ROOT or a ROOT containing only operator-placed
  files (a `.envrc`, a README). The function now requires a marker
  from the actual v1.2.4 layout (`bin/pkg-framework` or
  `lib/framework.sh` directly under ROOT) before renaming anything
  aside. Empty or operator-curated ROOTs are left alone.
- **Stale `.staging.<id>.<pid>` sweep.** Interrupted installs
  used to leak a `versions/.staging.<id>.<pid>` directory that no
  later pass cleaned up. `install_via_tarball` and `install_via_git`
  now `rm -rf versions/.staging.*` at the top of their bodies, so
  retries do not accumulate.
- **`prune_old_versions` input-domain comment.** The unquoted
  `for v in $(ls ...)` loop is safe because every entry under
  `versions/` is written by the installer using an id from
  `ref_to_id`, which sanitises to `[A-Za-z0-9.+-]`. A comment now
  documents the assumption so the next reader does not add a
  shellcheck-disable and forget.

### Migration

For consumers using the curl|bash one-liner, no action is required.
The next install or re-install lays down the new layout
automatically. Operators who hardcoded `$PKG_FRAMEWORK_HOME` in
their own scripts should switch to `$PKG_FRAMEWORK_ROOT`; the old
name will be removed in v1.4.0.

The note in [1.2.4]'s text about `pkg-framework upgrade` still
applies: `upgrade` mutates a consumer repo's vendored files and the
pin, not the framework install. The install itself is upgraded by
re-running this installer.

## [1.2.4] - 2026-05-24

Hotfix for a second-order case of the v1.2.2 finding #4. vigil hit
this on the next CI run after upgrading to v1.2.3:

    pkg-framework: ERROR: {:timestamp=>"...", :message=>"Created
    package", :path=>"...rpm"}
    /__w/vigil/vigil/dist/...rpm missing or empty

### Root cause

v1.2.2 routed the framework's own log/section/run chatter to stderr
so `artifact=$(_pkg_fpm_deb)` would capture exactly the artifact
path. The remaining hole: fpm itself writes a one-line
`Created package` log to stdout on success. Our `_pkg_fpm_deb` /
`_pkg_fpm_rpm` invoked fpm through `run`, which passed fpm's stdout
straight through to the caller's command substitution. The captured
artifact value became two lines (fpm's log line + our path),
`_pkg_make_reproducible` and `_pkg_validate_artifact` then operated
on the corrupted value and the build failed with `missing or empty`
for an artifact that was in fact valid.

### Fixed

- `_pkg_fpm_deb` and `_pkg_fpm_rpm` redirect fpm's stdout to stderr.
  The artifact-path return channel is now strictly the explicit
  `printf '%s' "$out_file"` at the end of each function.

### Tests

- `tests/smoke/test_e2e_package_build.sh` fpm shim now writes a
  `Created package` log line to stdout, mimicking real fpm.
- Step 1 of the smoke now asserts the captured artifact path
  contains no `{` and no `=>` (the exact fragments that bled
  through pre-v1.2.4), not just "single line". A regression of
  this class would have been silently green before.

### Migration

vigil and any consumer pinned to <= v1.2.3:

    pkg-framework upgrade
    pkg-framework verify

## [1.2.3] - 2026-05-24

Patch release for downstream GitHub Actions cache enforcement. vigil
synced v1.2.2 and hit a GitHub-hosted runner failure before CI could
start because the vendored workflow template pinned an older
`actions/cache` v4 commit that is now rejected by cache-action
enforcement. The source of truth is the framework template, not vigil.

### Fixed

- Updated both `actions/cache` pins in `lib/pkg-build.yml.tmpl` from
  the GitHub-rejected v4.0.2 commit to v4.3.0
  (`0057852bfaa89a56745cba8c7296529d2fc39830`). Downstream consumers
  that run `pkg-framework sync --bump` vendor the accepted cache
  action pin and no longer fail before the workflow starts.
- Added `tests/unit/test_workflow_action_pins.sh`, a regression check
  that enforces SHA-pinned `uses:` lines with version comments in the
  vendored workflow template, rejects floating tags, rejects missing
  `# vX.Y.Z` comments, and prevents the deprecated cache commit from
  being reintroduced.

## [1.2.2] - 2026-05-23

Real-consumer fixes after vigil's first adoption. vigil hit ten
distinct bugs that only surface in a project with two binaries,
multi-line descriptions, docs, man pages, systemd units, and a real
fpm build path. vigil patched its vendored copy locally to unblock
CI; this release upstreams the fixes so vigil can `pkg-framework
sync --bump` and drop the drift. Every fix has a regression test
that would have caught the original bug.

### Fixed

- **CLI symlink resolution.** `bin/pkg-framework` derived its home
  from `${BASH_SOURCE[0]}` without resolving the symlink that
  `install.sh` creates. `~/.local/bin/pkg-framework version` failed
  with "framework VERSION not found at ~/.local/VERSION". Now uses
  `readlink -f` (with python3 / perl fallbacks for BSD readlink).
  Pinned by smoke step 6.
- **Workflow shell.** `lib/pkg-build.yml.tmpl` uses `source` in
  container jobs; debian/ubuntu containers default `run:` to dash,
  where `source` exits 127. Added workflow-level
  `defaults.run.shell: bash`. Pinned by a unit test that asserts
  either the default exists or no `source` remains.
- **Multi-line `PKG_DESCRIPTION` corrupted fpm args.**
  `_pkg_fpm_common_args` returned newline-delimited stdout that the
  caller split on lines into a bash array. A description with
  literal newlines spilled its second paragraph onto fpm's command
  line as a positional path, with the symptom "Cannot package the
  path '/tmp/.../monitor. One operator...'". `_pkg_fpm_common_args`
  now writes directly into a caller-supplied array via bash
  nameref. Multi-line descriptions land intact in both deb and rpm
  metadata; docs already promised this and now actually deliver.
- **fpm stdout pollution corrupted captured artifact path.**
  `_pkg_fpm_deb` and `_pkg_fpm_rpm` write `printf '%s' "$out_file"`
  as the return channel, but `section`/`log`/`run` also wrote to
  stdout. `artifact=$(_pkg_fpm_deb)` captured the entire build log
  followed by the path; `_pkg_validate_artifact` then complained
  the artifact was missing. `log`, `section`, and `run` now write
  to stderr globally; stdout is reserved for return values.
- **`_pkg_validate_artifact` SIGPIPE on > 20 entries.**
  `run dpkg-deb -c "$artifact" | head -20` and the rpm equivalent
  trip SIGPIPE on the producer when `head` exits early. Under
  `set -o pipefail` that fails the build for a valid artifact.
  Capture the full listing into a variable, then head from it.
- **Slim debian/ubuntu/fedora containers drop docs and man pages
  at install time.** The install-test job in `pkg-build.yml.tmpl`
  now removes `/etc/dpkg/dpkg.cfg.d/excludes` (and the
  `dpkg.cfg.d/docker` variant) before `apt-get install`, and
  strips `tsflags=nodocs` from `/etc/dnf/dnf.conf` before
  `dnf install`. The installed layout now matches the packaged
  layout, and `layout-check.sh` stops false-flagging.
- **`layout-check.sh` grep slash escapes** caused
  `grep: warning: stray \ before /` on Fedora. Removed the
  unnecessary backslashes from
  `'^ExecStart=.*(/home/|/tmp/|target/release/)'`.
- **Debian copyright pointed at `changelog.gz` for the license
  body**, which was wrong. `_pkg_emit_debian_copyright` now emits a
  machine-readable copyright file per
  `https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/`.
  GPL-2/3 and LGPL-3 and Apache-2.0 point at the matching
  `/usr/share/common-licenses/` body. Other licenses inline the
  text from `$REPO_ROOT/LICENSE` when available, or fall back to a
  source-URL pointer. vigil can now remove its `project_stage_extra`
  override after sync.

### Added

- **`PKG_CARGO_OFFLINE`** (optional, default off). When set to
  `1`, the framework runs `cargo fetch --locked` first and builds
  with `--frozen --offline`. The compile step cannot touch the
  network. Useful for reproducibility audits and sandboxed CI.
- **`PKG_DEB_ARTIFACT_SUFFIX`** (optional). Inserted between
  `${VERSION}` and `_amd64.deb` in the artifact filename. Produces
  e.g. `vigil-baseline_1.12.1-noble_amd64.deb` so per-distro
  builds in one OUTDIR do not collide. Defaults preserve v1.2.1
  filenames.
- **`PKG_RPM_RELEASE`** (optional, default `1`). Maps to fpm
  `--iteration` and to the `N` in
  `${PKG_NAME}-${VERSION}-N.x86_64.rpm`. Set to `1.fedora40` to
  tag per-distro rpms.
- **`tests/unit/test_v1_2_2_findings.sh`**. 15+ assertions tying
  each finding back to a regression test (multi-line
  PKG_DESCRIPTION via nameref, copyright format correctness,
  log/section/run write to stderr, layout-check slashes, workflow
  bash default + doc-exclude clearing, CLI readlink -f, cargo
  offline knob present, suffix/release knobs present).
- **`tests/smoke/test_e2e_package_build.sh`**. 9 checks across 6
  steps. Shims fpm, exercises the real `_pkg_fpm_deb`,
  `_pkg_fpm_rpm`, `_pkg_validate_artifact`, manifest emission, and
  the CLI symlink path. Would have caught every vigil bug above.
  `make smoke` runs both smoke files.

### Changed

- **Every `uses:` action in the workflow template
  (`lib/pkg-build.yml.tmpl`) is now pinned to a sha** with the
  human tag in a trailing comment. The framework's own workflows
  were pinned in v1.2.1; the template that consumers vendor was
  the missing piece. After `pkg-framework sync`, every consumer
  inherits the pins automatically.
- `lib/project.sh.example` documents the three new knobs.
- `docs/customization-surface.md` documents the new knobs and
  pins the multi-line `PKG_DESCRIPTION` guarantee.
- `docs/troubleshooting.md` gains four new entries (#8 multi-line
  description corruption, #9 SIGPIPE on validate, #10 install-time
  doc stripping, #11 CLI through symlink). Each tells the operator
  exactly which version fixed it and what to do.

### Tracked follow-ups (not in this PR)

- `actions/attest-build-provenance` (still waiting on a verified
  sha pin for that action).
- Reproducible-build cross-verifier: a second matrix run that
  rebuilds the release tarball and compares sha256 against the
  attached sidecar.

### Migration

vigil and any other consumer pinned to `<= v1.2.1`:

```sh
pkg-framework upgrade   # sync --bump to v1.2.2
pkg-framework verify    # confirm clean
```

After sync, vigil can remove its local drift patches in
`pkg/lib/framework.sh` and `.github/workflows/pkg-build.yml`, and
drop the `project_stage_extra` override for `debian/copyright`.

## [1.2.1] - 2026-05-23

Supply-chain hardening. No new operator-facing features; this is
the patch that makes the framework worthy of being a build trust
root for vigil and other consumers.

### Changed

- Every `uses:` line in `.github/workflows/ci.yml` and
  `.github/workflows/release.yml` is now pinned to a sha with the
  human tag in a trailing comment. Floating tags
  (`actions/checkout@v4`, `softprops/action-gh-release@v2`) are
  gone. Re-tagged releases of those actions can no longer change
  what runs in our pipelines without a CODEOWNER review of the new
  sha.
- `install.sh` defaults to the latest published release tag (via
  `git ls-remote --tags --sort=-v:refname`), not `main`. A
  curl-piped installer that defaulted to a moving branch was the
  textbook supply-chain footgun this fix closes. `main` remains
  reachable via `PKG_FRAMEWORK_REF=main` but the installer prints
  a loud "NOT recommended" line when it falls back.
- `install.sh` verifies the published `sha256` sidecar against the
  downloaded tarball before extracting. Default behavior when the
  ref is a release tag and `curl + sha256sum + tar` are all
  present. Falls back to `git clone` when any of those are missing.
  `PKG_FRAMEWORK_METHOD=tarball` makes verification mandatory and
  refuses the fallback; `PKG_FRAMEWORK_METHOD=git` skips the
  tarball path entirely.
- `release.yml` extract-changelog step now fails the workflow when
  the matching `## [VERSION]` section is absent. The pre-1.2.1
  shape silently dumped the whole CHANGELOG into the release notes,
  which papered over the release-prep bug of forgetting to write
  notes for the release being tagged.
- `release.yml` publish step gains `make_latest: true` so a v* tag
  push deterministically updates the "Latest" badge regardless of
  the action's default behavior.

### Added

- `SECURITY.md`. Disclosure contact, supported-versions matrix,
  the supply-chain commitments (deterministic tarballs, sha256
  sidecar, sha-pinned actions, latest-tag default in the
  installer), and the known gaps (no build provenance yet, no
  reproducible-build cross-verifier yet).
- `.github/CODEOWNERS`. Single line, `* @lousclues`. Required
  reviewer for every path; pairs with branch protection on `main`.

### Tracked follow-ups (not in this PR)

- Add `actions/attest-build-provenance` to `release.yml` for an
  in-toto attestation that the tarball came from this workflow at
  this commit. Pending verification of a stable sha for that
  action.
- Repo description + topics (`packaging`, `deb`, `rpm`,
  `reproducible-builds`). Set via `gh repo edit`, not a file
  change in this PR.

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

## [1.0.0] -- 2026-05-23

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
