#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# pkg-framework test harness. Discovers tests/unit/test_*.sh and runs
# each in a subshell, tallying pass/fail. Exit 0 if all pass.
#
# Usage: tests/run_tests.sh [pattern]
#   pattern: optional substring filter (e.g. "manifest").

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_HOME="$(cd -- "$HERE/.." && pwd)"
export FRAMEWORK_HOME
export TEST_LIB="$HERE/_assert.sh"

pattern="${1:-}"

mapfile -t tests < <(find "$HERE/unit" -type f -name 'test_*.sh' | sort)

pass=0
fail=0
failed_names=()

for t in "${tests[@]}"; do
    name=$(basename "$t")
    if [[ -n "$pattern" && "$name" != *"$pattern"* ]]; then
        continue
    fi
    printf '\n=== %s ===\n' "$name"
    if bash "$t"; then
        printf 'PASS  %s\n' "$name"
        pass=$(( pass + 1 ))
    else
        printf 'FAIL  %s\n' "$name"
        fail=$(( fail + 1 ))
        failed_names+=("$name")
    fi
done

printf '\n---\n%d passed, %d failed\n' "$pass" "$fail"
if [[ "$fail" -gt 0 ]]; then
    printf 'failures:\n'
    for n in "${failed_names[@]}"; do
        printf '  - %s\n' "$n"
    done
    exit 1
fi
