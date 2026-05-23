#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Smoke test: simulates onboarding a brand-new project end to end.
#
# Story:
#   1. operator scaffolds a fresh project via `pkg-framework new`.
#   2. every vendored file lands at the documented path.
#   3. `pkg-framework verify` exits 0 against the just-scaffolded tree.
#   4. operator accidentally edits a vendored file (drift).
#   5. `pkg-framework verify` exits 1 and names the drifted file.
#   6. `pkg-framework sync` restores the vendored file.
#   7. `pkg-framework verify` exits 0 again.
#   8. `pkg-framework status` reports drift=0.
#   9. `pkg-framework lint` exits 0 on the scaffolded manifest.
#  10. `pkg-framework dry-run` references the project name.
#  11. `pkg-framework doctor` runs without crashing.
#  12. repeated `pkg-framework new` refuses to clobber.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_HOME="$(cd -- "$HERE/../.." && pwd)"
CLI="$FRAMEWORK_HOME/bin/pkg-framework"

tmp=$(mktemp -d -t pkg-framework-smoke.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

fail=0
pass_msg() { printf '  ok   %s\n' "$*"; }
fail_msg() { printf '  FAIL %s\n' "$*" >&2; fail=$(( fail + 1 )); }
step()     { printf '\n--- %s ---\n' "$*"; }

assert_eq()      { if [[ "$1" == "$2" ]]; then pass_msg "$3"; else fail_msg "$3 (got='$1' want='$2')"; fi; }
assert_file()    { if [[ -e "$1" ]]; then pass_msg "exists: $1"; else fail_msg "missing: $1"; fi; }
assert_exec()    { if [[ -x "$1" ]]; then pass_msg "executable: $1"; else fail_msg "not executable: $1"; fi; }
assert_grep()    { if grep -qE "$1" "$2"; then pass_msg "$3"; else fail_msg "$3 (pattern $1 in $2)"; fi; }
assert_in_str()  { if [[ "$1" == *"$2"* ]]; then pass_msg "$3"; else fail_msg "$3 (substring '$2' not in output)"; fi; }

project="smoke-onboard"
target="$tmp/$project"
mkdir -p "$target"

# -------------------------------------------------------------------------
step "1. scaffold via 'pkg-framework new'"
# -------------------------------------------------------------------------
rc=0
"$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" new "$project" \
    >"$tmp/new.log" 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]]; then
    fail_msg "new exited $rc; log:"
    sed 's/^/    /' "$tmp/new.log" >&2
fi
assert_exec   "$target/pkg/build.sh"
assert_file   "$target/pkg/project.sh"
assert_file   "$target/pkg/lib/framework.sh"
assert_file   "$target/pkg/lib/layout-check.sh"
assert_file   "$target/pkg/lib/input-tests.sh"
assert_file   "$target/pkg/lib/VERSION"
assert_file   "$target/.github/workflows/pkg-build.yml"
assert_grep "^PKG_NAME=$project\$"            "$target/pkg/project.sh" "PKG_NAME substituted"
assert_grep "^PKG_PREFIX=SMOKE_ONBOARD\$"     "$target/pkg/project.sh" "PKG_PREFIX substituted"
fv=$(tr -d '\r\n' < "$FRAMEWORK_HOME/VERSION")
assert_grep "^FRAMEWORK_VERSION=$fv\$"        "$target/pkg/project.sh" "FRAMEWORK_VERSION pinned"

# -------------------------------------------------------------------------
step "2. 'pkg-framework verify' on clean scaffold (exits 0)"
# -------------------------------------------------------------------------
rc=0
"$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" verify --quiet \
    >"$tmp/verify1.log" 2>&1 || rc=$?
assert_eq "$rc" "0" "verify exits 0"

# -------------------------------------------------------------------------
step "3. introduce drift in a vendored file"
# -------------------------------------------------------------------------
printf '\n# accidental edit\n' >> "$target/pkg/lib/framework.sh"
rc=0
"$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" verify \
    >"$tmp/verify2.log" 2>&1 || rc=$?
assert_eq "$rc" "1" "verify exits 1 on drift"
assert_grep "framework.sh" "$tmp/verify2.log" "verify names the drifted file"

# -------------------------------------------------------------------------
step "4. 'pkg-framework sync' restores the vendored file"
# -------------------------------------------------------------------------
rc=0
"$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" sync \
    >"$tmp/sync.log" 2>&1 || rc=$?
assert_eq "$rc" "0" "sync exits 0"
rc=0
"$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" verify --quiet \
    >"$tmp/verify3.log" 2>&1 || rc=$?
assert_eq "$rc" "0" "verify exits 0 after sync"

# -------------------------------------------------------------------------
step "5. 'pkg-framework status' reports drift=0"
# -------------------------------------------------------------------------
status_out=$("$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" status 2>&1) || true
assert_in_str "$status_out" "framework=$fv" "status reports framework=$fv"
assert_in_str "$status_out" "drift=0"       "status reports drift=0"
assert_in_str "$status_out" "pinned=$fv"    "status reports pinned=$fv"

# -------------------------------------------------------------------------
step "6. 'pkg-framework lint' on scaffolded manifest"
# -------------------------------------------------------------------------
rc=0
"$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" lint \
    >"$tmp/lint.log" 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]]; then
    sed 's/^/    /' "$tmp/lint.log" >&2
fi
assert_eq "$rc" "0" "lint exits 0 on example manifest"

# -------------------------------------------------------------------------
step "7. 'pkg-framework dry-run' references the project"
# -------------------------------------------------------------------------
dr_out=$("$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" dry-run 2>&1) || true
assert_in_str "$dr_out" "$project" "dry-run mentions project name"
assert_in_str "$dr_out" "deb"      "dry-run mentions deb"
assert_in_str "$dr_out" "rpm"      "dry-run mentions rpm"

# -------------------------------------------------------------------------
step "8. 'pkg-framework doctor' reports a verdict (no crash)"
# -------------------------------------------------------------------------
"$CLI" doctor >"$tmp/doctor.log" 2>&1 || true
if [[ -s "$tmp/doctor.log" ]]; then
    pass_msg "doctor produces output"
else
    fail_msg "doctor produced empty output"
fi

# -------------------------------------------------------------------------
step "9. cli refuses to clobber on repeated 'new'"
# -------------------------------------------------------------------------
rc=0
"$CLI" --framework-path "$FRAMEWORK_HOME" --target "$target" new "$project" \
    >"$tmp/new2.log" 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]]; then
    pass_msg "second new exits non-zero (rc=$rc)"
else
    fail_msg "second new should have refused but exited 0"
fi
assert_grep "refuses" "$tmp/new2.log" "second new mentions refuses"

# -------------------------------------------------------------------------
printf '\n---\n'
if [[ "$fail" -gt 0 ]]; then
    printf 'smoke FAILED (%d check(s))\n' "$fail" >&2
    exit 1
fi
printf 'smoke clean: onboarding round trip works end to end\n'
