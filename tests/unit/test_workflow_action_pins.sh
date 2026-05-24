#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Regression test for the v1.2.3 cache-action pin fix. GitHub
# rejected an older actions/cache v4 commit even though it was
# sha-pinned, causing downstream consumers (vigil) to fail before
# their vendored workflow could start. This test enforces the policy
# for every `uses:` line in the vendored workflow template and keeps
# the rejected cache commit from returning.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

file="$FRAMEWORK_HOME/lib/pkg-build.yml.tmpl"
fixed_cache_version="4.3.0"
fixed_cache_sha="0057852bfaa89a56745cba8c7296529d2fc39830"
# Split this so a repo-wide grep for the rejected SHA stays clean.
banned_cache_sha="0c45773b623bea8c8e75f6c82b208c3c""f94ea4f9"

version_ge() {
    local have=$1 want=$2
    local have_major have_minor have_patch want_major want_minor want_patch
    IFS=. read -r have_major have_minor have_patch <<< "$have"
    IFS=. read -r want_major want_minor want_patch <<< "$want"
    if (( have_major != want_major )); then
        (( have_major > want_major ))
        return $?
    fi
    if (( have_minor != want_minor )); then
        (( have_minor > want_minor ))
        return $?
    fi
    (( have_patch >= want_patch ))
}

uses_count=0
cache_count=0
while IFS= read -r line; do
    uses_count=$(( uses_count + 1 ))
    uses=${line#*uses: }
    action=${uses%%@*}
    rest=${uses#*@}
    sha=${rest%% *}

    if printf '%s' "$sha" | grep -Eq '^[0-9a-f]{40}$'; then
        ok "sha-pinned uses line: $action"
    else
        fail "unpinned or malformed uses line: $line"
        continue
    fi

    if printf '%s\n' "$line" | grep -Eq '# v[0-9]+\.[0-9]+\.[0-9]+$'; then
        ok "version comment present: $action"
    else
        fail "missing version comment: $line"
    fi

    if [[ "$action" == "actions/cache" ]]; then
        cache_count=$(( cache_count + 1 ))
        if [[ "$sha" == "$banned_cache_sha" ]]; then
            fail "banned actions/cache SHA still present"
        else
            ok "actions/cache does not use the rejected commit"
        fi
        if [[ "$sha" == "$fixed_cache_sha" ]]; then
            ok "actions/cache uses the selected fixed SHA"
        else
            fail "actions/cache SHA drifted: got $sha expected $fixed_cache_sha"
        fi
        version_comment=$(printf '%s\n' "$line" | sed -E 's/.*# v([0-9]+\.[0-9]+\.[0-9]+)$/\1/')
        if version_ge "$version_comment" "$fixed_cache_version"; then
            ok "actions/cache version comment >= v$fixed_cache_version"
        else
            fail "actions/cache version comment too old: v$version_comment < v$fixed_cache_version"
        fi
    fi
done < <(grep -E 'uses: [^ ]+@' "$file")

assert_eq "$uses_count" "9" "workflow template still has 9 action uses"
assert_eq "$cache_count" "2" "workflow template has exactly two actions/cache uses"

if [[ "${_assert_fail_count:-0}" -gt 0 ]]; then
    printf '\n%d assertion(s) failed in %s\n' "${_assert_fail_count}" "$(basename "$0")" >&2
    exit 1
fi
printf '\nok: workflow action pins are all sha-pinned and cache uses v%s\n' "$fixed_cache_version"
