#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Tiny assertion helpers for the pkg-framework bash tests. Sourced by
# every test_*.sh; not executable on its own.

# shellcheck disable=SC2034
ASSERT_LIB_LOADED=1

_assert_fail_count=0

_assert_loc() {
    # Caller frame: caller 1 -> file + line of assert_*.
    local line file
    read -r line _ file < <(caller 1) || true
    printf '%s:%s' "${file:-?}" "${line:-?}"
}

fail() {
    _assert_fail_count=$(( _assert_fail_count + 1 ))
    printf '  FAIL  (%s) %s\n' "$(_assert_loc)" "$*" >&2
}

ok() {
    printf '  ok    %s\n' "$*"
}

assert_eq() {
    # assert_eq <actual> <expected> [label]
    local actual=$1 expected=$2 label="${3:-values equal}"
    if [[ "$actual" == "$expected" ]]; then
        ok "$label"
    else
        fail "$label: actual='$actual' expected='$expected'"
    fi
}

assert_neq() {
    local actual=$1 forbidden=$2 label="${3:-values differ}"
    if [[ "$actual" != "$forbidden" ]]; then
        ok "$label"
    else
        fail "$label: both='$actual'"
    fi
}

assert_contains() {
    local haystack=$1 needle=$2 label="${3:-haystack contains needle}"
    if [[ "$haystack" == *"$needle"* ]]; then
        ok "$label"
    else
        fail "$label: needle='$needle' not in haystack='$haystack'"
    fi
}

assert_not_contains() {
    local haystack=$1 needle=$2 label="${3:-haystack does not contain needle}"
    if [[ "$haystack" != *"$needle"* ]]; then
        ok "$label"
    else
        fail "$label: needle='$needle' is in haystack"
    fi
}

assert_rc() {
    # assert_rc <expected-rc> <cmd...>
    local expected=$1
    shift
    local actual=0
    "$@" >/dev/null 2>&1 || actual=$?
    if [[ "$actual" == "$expected" ]]; then
        ok "rc=$expected ($*)"
    else
        fail "rc mismatch ($*): actual=$actual expected=$expected"
    fi
}

assert_file_exists() {
    local p=$1
    if [[ -e "$p" ]]; then
        ok "exists: $p"
    else
        fail "missing: $p"
    fi
}

assert_file_executable() {
    local p=$1
    if [[ -x "$p" ]]; then
        ok "executable: $p"
    else
        fail "not executable: $p"
    fi
}

assert_done() {
    if [[ "$_assert_fail_count" -eq 0 ]]; then
        exit 0
    fi
    printf '\n%d assertion(s) failed\n' "$_assert_fail_count" >&2
    exit 1
}
