#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Unit tests for framework.sh helpers: log, run, retry,
# validate_git_commit_hex, install_to.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"
# shellcheck disable=SC1091
source "$FRAMEWORK_HOME/lib/framework.sh"

# --- validate_git_commit_hex ---
assert_rc 0 validate_git_commit_hex unknown
assert_rc 0 validate_git_commit_hex 0123456789abcdef0123456789abcdef01234567
assert_rc 1 validate_git_commit_hex 0123456789ABCDEF0123456789ABCDEF01234567
assert_rc 1 validate_git_commit_hex deadbeef
assert_rc 1 validate_git_commit_hex 0123456789abcdef0123456789abcdef0123456g
assert_rc 1 validate_git_commit_hex ''

# --- retry ---
TRIES_FILE=$(mktemp)
echo 0 > "$TRIES_FILE"
flaky() {
    local n
    n=$(cat "$TRIES_FILE")
    n=$((n + 1))
    echo "$n" > "$TRIES_FILE"
    [[ "$n" -ge 3 ]]
}
if retry 5 0 flaky; then
    ok "retry succeeded on 3rd attempt"
    actual=$(cat "$TRIES_FILE")
    assert_eq "$actual" 3 "retry called function 3 times"
else
    fail "retry did not succeed within 5 attempts"
fi
rm -f "$TRIES_FILE"

# retry should fail when the command always fails.
always_fail() { return 1; }
if retry 2 0 always_fail; then
    fail "retry should have failed but returned 0"
else
    ok "retry returned non-zero after exhausting attempts"
fi

# --- install_to ---
TMP=$(mktemp -d)
echo content > "$TMP/src"
install_to "$TMP/src" "$TMP/nested/path/dest" 0640
assert_file_exists "$TMP/nested/path/dest"
mode=$(stat -c '%a' "$TMP/nested/path/dest")
assert_eq "$mode" 640 "install_to applied mode 0640"
rm -rf "$TMP"

assert_done
