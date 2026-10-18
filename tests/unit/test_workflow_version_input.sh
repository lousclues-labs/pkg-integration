#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Regression test for the v1.4.0 dispatch-input fix. The workflow's
# "derive version" step wrote ${{ github.event.inputs.version }} straight
# into its shell script, so a dispatched version ran as code. It now
# reaches the shell through env alone, and only a semantic version is
# taken. The step's own script is run here against good and hostile
# values. The build matrix also keeps to a Fedora release still
# supported upstream.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

file="$FRAMEWORK_HOME/lib/pkg-build.yml.tmpl"
# Split so this file's own text is not a match.
expression='${{ github.event.inputs''.version }}'

# 1. Every mention of the input is an env assignment, never script text.
seen=0
while IFS= read -r line; do
    seen=$(( seen + 1 ))
    if [[ "$line" =~ ^\ +[A-Z_]+:\ \$\{\{\ github\.event\.inputs\.version\ \}\}$ ]]; then
        ok "inputs.version passes through env: ${line#"${line%%[! ]*}"}"
    else
        fail "inputs.version outside an env assignment: $line"
    fi
done < <(grep -F "$expression" "$file")
if (( seen == 0 )); then
    fail "inputs.version is not passed to any step"
fi

# 2. The step's script, as the runner would run it.
script=$(awk '
    /- name: derive version/ { in_step = 1; next }
    in_step && /^        run: \|$/ { in_run = 1; next }
    in_run {
        if ($0 ~ /^          /) { sub(/^          /, ""); print; next }
        exit
    }
' "$file")
if [[ -z "$script" ]]; then
    fail "could not find the derive version step's script"
fi

# Runs the script with INPUT_VERSION=$1 in a project whose Cargo.toml says
# 9.8.7; prints its exit code and what it wrote to GITHUB_OUTPUT.
run_step() {
    local dir="$TMP/run.$RANDOM$RANDOM"
    mkdir -p "$dir"
    printf '[package]\nname = "x"\nversion = "9.8.7"\n' > "$dir/Cargo.toml"
    (cd "$dir" && INPUT_VERSION="$1" GITHUB_OUTPUT="$dir/out" bash -e -c "$script") >/dev/null 2>&1
    local rc=$?
    printf '%s|%s' "$rc" "$(cat "$dir/out" 2>/dev/null)"
    if [[ -e "$dir/pwned" ]]; then
        printf '|ran'
    fi
}

for good in "1.2.3" "0.4.0" "1.2.3-rc.1" "2.0.0+build.7"; do
    assert_eq "$(run_step "$good")" "0|version=$good" "takes $good"
done
assert_eq "$(run_step "")" "0|version=9.8.7" "empty reads Cargo.toml"
for bad in "1.2" "01.2.3" "v1.2.3" "1.2.3 " '1.2.3; touch pwned' '$(touch pwned)' \
    '`touch pwned`' $'1.2.3\nversion=6.6.6'; do
    assert_eq "$(run_step "$bad")" "1|" "refuses $(printf '%q' "$bad")"
done

# 3. No Fedora image older than the matrix's. Fedora 40 reached its end of
# life in May 2025; the floor rises as Fedora's releases do.
floor=44
while IFS= read -r image; do
    n=${image##*fedora:}
    if (( n >= floor )); then
        ok "fedora:$n is $floor or later"
    else
        fail "fedora:$n is older than $floor; build on a release Fedora still supports"
    fi
done < <(grep -oE 'image: fedora:[0-9]+' "$file")

assert_done
