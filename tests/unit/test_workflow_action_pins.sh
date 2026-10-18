#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Regression test for the v1.2.3 cache-action pin fix. GitHub
# rejected an older actions/cache v4 commit even though it was
# sha-pinned, causing downstream consumers (vigil) to fail before
# their vendored workflow could start. This test enforces the policy
# for every `uses:` line in the vendored workflow template and keeps
# the rejected cache commit from returning.
#
# Since v1.4.1 each pin's comment must also name the release its commit
# truly is. Through v1.4.0 the template pinned actions/checkout's v4.1.1
# commit under the comment v4.1.7, and nothing here could tell. Each
# commit below was resolved from its tag when it was chosen, with
# `gh api repos/<action>/git/ref/tags/<tag>`; a new pin joins the table
# the same way.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

file="$FRAMEWORK_HOME/lib/pkg-build.yml.tmpl"
fixed_cache_version="6.1.0"
fixed_cache_sha="55cc8345863c7cc4c66a329aec7e433d2d1c52a9"
# Split this so a repo-wide grep for the rejected SHA stays clean.
banned_cache_sha="0c45773b623bea8c8e75f6c82b208c3c""f94ea4f9"

declare -A release_of=(
    [actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1]=v7.0.1
    [actions/cache@55cc8345863c7cc4c66a329aec7e433d2d1c52a9]=v6.1.0
    [actions/upload-artifact@043fb46d1a93c77aae656e7c1c64a875d1fc6a0a]=v7.0.1
    [actions/download-artifact@3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c]=v8.0.1
)

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

    named=${line##*# }
    release=${release_of[$action@$sha]:-}
    if [[ -z "$release" ]]; then
        fail "a pin no tag was resolved for: $action@$sha"
    elif [[ "$named" == "$release" ]]; then
        ok "$action@${sha:0:7} is $release, as its comment says"
    else
        fail "$action@${sha:0:7} is $release, but its comment says $named"
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
