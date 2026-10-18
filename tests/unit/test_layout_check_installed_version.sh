#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Regression test for v1.4.1: layout-check.sh compares the upstream part of
# a deb's installed version with the version the source project declares.
#
# dpkg-query reports ${Version} as [epoch:]upstream[-debian_revision], so a
# consumer that builds its debs with --iteration, one revision for each
# codename as vigil does, installs 1.12.2-1, and v1.4.0 failed every such
# install test with "installed version 1.12.2-1 != expected 1.12.2". The fix
# was made in two downstream copies first, lousclues-pkg's 1.0.1 and vigil's
# vendored 1.2.5, and is made here with the same lines. An exact match is
# still taken first, and an rpm's %{VERSION} carries no release to strip.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

LAYOUT_CHECK="$FRAMEWORK_HOME/lib/layout-check.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/project.sh" <<'EOF'
PKG_NAME=demo
PKG_PREFIX=DEMO
EOF

# A stand-in dpkg-query, first on PATH, answers the version in $INSTALLED.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/dpkg-query" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$INSTALLED"
EOF
chmod +x "$TMP/bin/dpkg-query"

# The version section's verdict for an installed version and the expected
# one, in the installed mode the workflow runs (ROOT empty). The other
# sections look at this host's filesystem and are not read here.
verdict() {
    INSTALLED=$1 ACTUAL=$2 PATH="$TMP/bin:$PATH" PROJECT_SH="$TMP/project.sh" ROOT="" EXT=deb \
        bash "$LAYOUT_CHECK" 2>&1 | grep -E '^  (ok|FAIL): +installed version '
}

assert_eq "$(verdict 1.12.2 1.12.2)" \
    "  ok:   installed version 1.12.2 matches expected 1.12.2" \
    "an exact version matches"
assert_eq "$(verdict 1.12.2-1 1.12.2)" \
    "  ok:   installed version 1.12.2-1 (upstream 1.12.2) matches expected 1.12.2" \
    "a debian revision is not part of the upstream version"
assert_eq "$(verdict 2:1.12.2-1 1.12.2)" \
    "  ok:   installed version 2:1.12.2-1 (upstream 1.12.2) matches expected 1.12.2" \
    "nor is an epoch"
assert_eq "$(verdict 1.12.2-rc.1-3 1.12.2-rc.1)" \
    "  ok:   installed version 1.12.2-rc.1-3 (upstream 1.12.2-rc.1) matches expected 1.12.2-rc.1" \
    "only the last hyphen begins the revision"
assert_eq "$(verdict 1.12.2-1 1.12.2-1)" \
    "  ok:   installed version 1.12.2-1 matches expected 1.12.2-1" \
    "a full deb version given as expected matches exactly"
assert_eq "$(verdict 1.12.3-1 1.12.2)" \
    "  FAIL: installed version 1.12.3-1 != expected 1.12.2" \
    "another upstream version still fails"
assert_eq "$(verdict 1.12.2.1 1.12.2)" \
    "  FAIL: installed version 1.12.2.1 != expected 1.12.2" \
    "a longer version without a revision still fails"
assert_eq "$(verdict 1.12.2-2 1.12.2-1)" \
    "  FAIL: installed version 1.12.2-2 != expected 1.12.2-1" \
    "a full deb version given as expected is not normalized away"

assert_done
