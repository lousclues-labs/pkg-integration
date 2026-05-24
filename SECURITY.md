<!-- SPDX-License-Identifier: GPL-3.0-only -->

# Security policy

`pkg-framework` is a build pipeline that consumers (vigil, shroud,
others) pin as a trust dependency. A compromise here lands in every
downstream artifact. This file documents how to report a problem
and what the supply-chain story is.

## Reporting a vulnerability

Email **security@lousclues.com**. Include:

- The version (tag) and commit sha you tested.
- Reproduction steps.
- Impact assessment as you see it.

PGP is not currently published. If you need encryption-in-transit
before sharing details, say so in your first email and we will
exchange a current key out of band. Removing the prior
`lousclues.com/pgp` claim is intentional: the page never went live,
and a security contact must not advertise infrastructure it does
not operate.

Expect a first reply within 72 hours. We will acknowledge, agree on
a disclosure timeline (default: 90 days for issues that ship in
artifacts; sooner for active exploitation), and credit reporters in
the `CHANGELOG.md` entry that fixes the issue unless asked otherwise.

Please do not file public issues for security topics. A
`SECURITY-PENDING` placeholder issue is fine if you need to coordinate
without disclosing.

## Supported versions

The framework follows semver. Patch fixes land on the current minor
line; the previous minor receives security backports for 90 days
after the next minor releases. Anything older is out of scope.

| Version | Status |
|---|---|
| 1.2.x   | current; security + bug fixes |
| 1.1.x   | security backports through next minor + 90d |
| 1.0.x   | end of life |

## Supply-chain commitments

For a build pipeline, "secure" is mostly about the integrity of what
ships and what consumers can verify. The current state:

- **Every release is published with a sha256 sidecar.** The release
  workflow attaches `pkg-framework-vX.Y.Z.tar.gz` and
  `pkg-framework-vX.Y.Z.tar.gz.sha256` to every GitHub Release.
- **Releases are deterministic.** The tarball is built with sorted
  file order, `owner=0/group=0`, and an mtime fixed to the tag
  commit's `SOURCE_DATE_EPOCH`. Two runs produce byte-identical
  output.
- **Every `uses:` line in CI and release pipelines is pinned to a
  sha**, with the human-readable tag in a trailing comment. Floating
  tags are not allowed.
- **The one-liner installer (`install.sh`) defaults to the latest
  release tag**, not `main`. When the requested ref is a release
  tag, the installer downloads the published tarball, verifies its
  sha256 against the sidecar from the same release, and only then
  extracts. `PKG_FRAMEWORK_METHOD=tarball` makes this path mandatory.
- **Releases are emitted via GitHub Releases**; URLs are stable and
  guess-resistant. The release workflow uses a pinned action and
  carries `fail_on_unmatched_files: true` so a partial upload fails
  the publish.

## Known gaps (tracked)

- **No build provenance / in-toto attestation yet.** Plan:
  `actions/attest-build-provenance` once we pin a sha we have
  verified. Until then, the sha256 sidecar is the only artifact
  integrity signal.
- **No reproducible-build cross-verifier in CI.** A second matrix
  run that rebuilds the tarball and compares sha256 would harden
  the determinism claim. Tracked.

If you find a gap that is not on this list, please report it as a
vulnerability per the section above; we will add it.
