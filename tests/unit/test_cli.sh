#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Unit tests for the pkg-framework CLI: version, new, sync, verify.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

CLI="$FRAMEWORK_HOME/bin/pkg-framework"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- version ---
fv_expected=$(tr -d '\r\n' < "$FRAMEWORK_HOME/VERSION")
fv_actual=$("$CLI" version)
assert_eq "$fv_actual" "$fv_expected" 'pkg-framework version prints VERSION'

# --- new <name> ---
NEW_DIR="$TMP/new-project"
install -d -m 0755 "$NEW_DIR"
"$CLI" new demo --target "$NEW_DIR" >/dev/null
assert_file_exists "$NEW_DIR/pkg/build.sh"
assert_file_executable "$NEW_DIR/pkg/build.sh"
assert_file_exists "$NEW_DIR/pkg/project.sh"
assert_file_exists "$NEW_DIR/pkg/lib/framework.sh"
assert_file_exists "$NEW_DIR/pkg/lib/layout-check.sh"
assert_file_exists "$NEW_DIR/pkg/lib/input-tests.sh"
assert_file_exists "$NEW_DIR/pkg/lib/VERSION"
assert_file_exists "$NEW_DIR/.github/workflows/pkg-build.yml"

pkg_name=$(awk -F= '/^PKG_NAME=/ {print $2; exit}' "$NEW_DIR/pkg/project.sh")
assert_eq "$pkg_name" 'demo' 'new substitutes PKG_NAME'
pkg_prefix=$(awk -F= '/^PKG_PREFIX=/ {print $2; exit}' "$NEW_DIR/pkg/project.sh")
assert_eq "$pkg_prefix" 'DEMO' 'new substitutes PKG_PREFIX uppercase'
pinned=$(awk -F= '/^FRAMEWORK_VERSION=/ {print $2; exit}' "$NEW_DIR/pkg/project.sh")
assert_eq "$pinned" "$fv_expected" 'new pins FRAMEWORK_VERSION'

# --- new refuses to clobber ---
out=$("$CLI" new demo --target "$NEW_DIR" 2>&1) && rc=0 || rc=$?
assert_neq "$rc" 0 'new refuses to clobber existing files'
assert_contains "$out" 'refuses to overwrite' 'reports refusal reason'

# --- verify (clean) ---
out=$("$CLI" verify --target "$NEW_DIR" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 'verify on freshly-scaffolded project: clean'

# --- verify (drift) ---
echo '# tampered' >> "$NEW_DIR/pkg/lib/framework.sh"
out=$("$CLI" verify --target "$NEW_DIR" 2>&1) && rc=0 || rc=$?
assert_neq "$rc" 0 'verify on tampered framework.sh: drift'
assert_contains "$out" 'DRIFT  pkg/lib/framework.sh' 'reports the drifted file'

# --- sync (restores drift) ---
"$CLI" sync --target "$NEW_DIR" >/dev/null
out=$("$CLI" verify --target "$NEW_DIR" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 0 'verify is clean after sync restores the tampered file'

# --- sync (version-pin mismatch refused without --bump) ---
sed -i.bak -E "s/^FRAMEWORK_VERSION=.*/FRAMEWORK_VERSION=99.99.99/" "$NEW_DIR/pkg/project.sh"
rm -f "$NEW_DIR/pkg/project.sh.bak"
out=$("$CLI" sync --target "$NEW_DIR" 2>&1) && rc=0 || rc=$?
assert_neq "$rc" 0 'sync refuses version-pin mismatch'
assert_contains "$out" 'sync --bump' 'instructs to use --bump'

# --- sync --bump rewrites the pin ---
"$CLI" sync --bump --target "$NEW_DIR" >/dev/null
pinned_after=$(awk -F= '/^FRAMEWORK_VERSION=/ {print $2; exit}' "$NEW_DIR/pkg/project.sh")
assert_eq "$pinned_after" "$fv_expected" 'sync --bump rewrites the pin'

# --- unknown subcommand exits 64 ---
out=$("$CLI" wat 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 64 'unknown subcommand exits 64'

# --- no subcommand exits 64 ---
out=$("$CLI" 2>&1) && rc=0 || rc=$?
assert_eq "$rc" 64 'no subcommand exits 64'

assert_done
