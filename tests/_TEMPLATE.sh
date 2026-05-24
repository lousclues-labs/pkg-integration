#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Template for a new unit test. Copy to tests/unit/test_<name>.sh,
# chmod +x, and replace the body.
#
# Conventions (see tests/README.md):
#   - set -uo pipefail (NOT -e; assertions must all run)
#   - source ../_assert.sh for the helper namespace
#   - use $FRAMEWORK_HOME for repo paths; do NOT hardcode them
#   - build fixtures under $(mktemp -d); trap to clean up
#   - end with assert_done

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# Locate _assert.sh. After this template is copied to
# tests/unit/test_<name>.sh you can replace the next 3 lines with
# the canonical one-liner the other unit tests use:
#     source "$HERE/../_assert.sh"
ASSERT="$HERE/_assert.sh"
[[ -r "$ASSERT" ]] || ASSERT="$HERE/../_assert.sh"
# shellcheck disable=SC1090
source "$ASSERT"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# -------------------------------------------------------------------------
# Replace the body below with the assertions your test needs. Examples
# of each helper (delete what you do not use):
# -------------------------------------------------------------------------

# String equality.
assert_eq "$(printf 'hello')" "hello" "printf hello returns hello"

# Substring presence on a captured output.
out=$(printf 'pkg-framework v1.2.3\n')
assert_contains "$out" "pkg-framework"
assert_contains "$out" "v1.2.3"

# Exit-code check on a real command.
assert_rc 0 true
assert_rc 1 false

# File assertions on a fixture you built under $TMP.
install -D -m 0755 /dev/null "$TMP/usr/bin/demo"
assert_file_exists "$TMP/usr/bin/demo"
assert_file_executable "$TMP/usr/bin/demo"

# Manual ok/fail when the comparison is non-trivial.
if [[ -d "$TMP" ]]; then
    ok "tmp dir is a directory"
else
    fail "tmp dir is not a directory: $TMP"
fi

assert_done
