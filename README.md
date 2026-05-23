<!-- SPDX-License-Identifier: GPL-3.0-only -->

# pkg-framework

Shared deb / rpm build pipeline for lousclues-labs Rust projects. The
framework lives at `lousclues-labs/pkg-integration` as the source of
truth. Source repositories vendor it into `pkg/lib/` via the
`pkg-framework` CLI, then declare a small manifest in `pkg/project.sh`.

## What you get

A single source-of-truth build pipeline that:

- Produces reproducible deb (Debian, Ubuntu) and rpm (Fedora) artifacts
  with a stable `SOURCE_DATE_EPOCH`.
- Emits a JSON manifest sidecar for every artifact (schema
  `pkg-framework-manifest/1`).
- Runs the same input validation, stage validation, and installed-layout
  checks across every project.
- Pins `fpm`, container images, and toolchain versions in one place.

What the source repo still owns:

- The actual Rust source.
- `pkg/project.sh` -- data only (package metadata, deps, layout
  assertions) plus optional shell hooks for project-specific staging.
- A thin entry-point `pkg/build.sh` (two source lines + one function
  call) that the framework's templates scaffold for you.

## Quick start (new project)

```sh
cd my-rust-project
/path/to/pkg-integration/bin/pkg-framework new my-rust-project
$EDITOR pkg/project.sh    # fill in the manifest
git add pkg/ .github/workflows/pkg-build.yml
git commit -m 'pkg: adopt pkg-framework v1.0.0'
```

The scaffolder writes:

```
pkg/
  build.sh              # entry point (executable wrapper)
  project.sh            # manifest (you edit this)
  lib/
    framework.sh        # vendored
    layout-check.sh     # vendored
    input-tests.sh      # vendored
    VERSION             # vendored
.github/workflows/
  pkg-build.yml         # vendored
```

## Quick start (existing project)

Run `pkg-framework sync` from the repo root. The CLI refuses to clobber
any pre-existing file; for a first conversion, copy the example manifest
and tailor it:

```sh
cd existing-project
/path/to/pkg-integration/bin/pkg-framework new my-project       # scaffolds; abort if it refuses
```

For projects already on a previous framework version:

```sh
/path/to/pkg-integration/bin/pkg-framework sync --bump
```

## Subcommands

| Command | What it does |
|---|---|
| `pkg-framework version` | Prints the framework's pinned version. |
| `pkg-framework new <name>` | Scaffolds `pkg/`, `pkg/lib/`, and `.github/workflows/pkg-build.yml` in the current dir. Refuses if any target file exists. |
| `pkg-framework sync [--bump]` | Refreshes vendored files in `pkg/lib/` and `.github/workflows/`. Refuses if the `FRAMEWORK_VERSION` pin in `pkg/project.sh` does not match the upstream `VERSION`, unless `--bump` is passed. |
| `pkg-framework verify [--quiet]` | Computes sha256 of every vendored file and compares against upstream. Exit 1 on drift. Runs in source-repo CI as the drift gate. |

## Documentation

- [porting guide](docs/porting-guide.md) -- step-by-step for converting
  an existing project to the framework.
- [customization surface](docs/customization-surface.md) -- the full
  manifest schema and every hook function, with concrete examples
  drawn from vigil and shroud.
- [versioning policy](docs/versioning.md) -- semver, deprecation
  windows, and the sync-or-stay contract.

## License

GPL-3.0-only. The artifacts produced by the framework inherit the
SPDX license declared in the source project's `pkg/project.sh`
(via fpm `--license`); the framework's license does not propagate to
those artifacts.
