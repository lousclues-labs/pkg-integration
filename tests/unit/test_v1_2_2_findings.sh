#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Unit tests pinning the v1.2.2 framework fixes against the bugs vigil
# found in its first real adoption. Each assertion ties back to a
# numbered finding in the v1.2.2 task brief.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"
# shellcheck disable=SC1091
source "$FRAMEWORK_HOME/lib/framework.sh"

# Globals the helpers expect. Most of these mirror what
# _pkg_setup_globals would set in a real build.
PKG_NAME="demo"
PKG_PREFIX="DEMO"
PKG_VENDOR="Lou's Clues Labs"
PKG_MAINTAINER="Lou <lou@example.com>"
PKG_HOMEPAGE_URL="https://example.com/demo"
PKG_SOURCE_URL="https://github.com/lousclues-labs/demo"
PKG_LICENSE_SPDX="GPL-3.0-only"
PKG_LICENSE_NAME="GPL-3.0-only"
PKG_COPYRIGHT_HOLDERS="Lou Junior"
PKG_COPYRIGHT_YEAR="2026"
VERSION="1.2.3"

# Multi-line description per the docs promise.
PKG_DESCRIPTION="First paragraph of the description.
Wrapped at a reasonable width.

Second paragraph after a blank line.
With its own continuation."

# --- Finding #3: multi-line PKG_DESCRIPTION survives _pkg_fpm_common_args ---
common_args=()
_pkg_fpm_common_args common_args

# The array layout is --name N --version V ... --description D --architecture native.
# Locate --description and assert the next element equals the full
# multi-line value verbatim.
desc_index=-1
for i in "${!common_args[@]}"; do
    if [[ "${common_args[$i]}" == "--description" ]]; then
        desc_index=$((i + 1))
        break
    fi
done
if [[ "$desc_index" -lt 0 ]]; then
    fail "common args did not include --description"
else
    assert_eq "${common_args[$desc_index]}" "$PKG_DESCRIPTION" \
        "multi-line description survives intact (one --description arg)"
fi

# Count --description occurrences; must be exactly one.
desc_count=0
for a in "${common_args[@]}"; do
    [[ "$a" == "--description" ]] && desc_count=$((desc_count + 1))
done
assert_eq "$desc_count" "1" "exactly one --description flag"

# --- Finding #8: debian copyright is real, not a changelog pointer ---
REPO_ROOT="$(mktemp -d)"
# No LICENSE file present -> GPL-3 branch points to common-licenses.
copy_out=$(_pkg_emit_debian_copyright)

assert_contains "$copy_out" "Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/" \
    "copyright declares the format header"
assert_contains "$copy_out" "Upstream-Name: $PKG_NAME" "copyright has Upstream-Name"
assert_contains "$copy_out" "Source: $PKG_SOURCE_URL" "copyright has Source"
assert_contains "$copy_out" "Files: *"                "copyright has Files: * stanza"
assert_contains "$copy_out" "Copyright: $PKG_COPYRIGHT_YEAR $PKG_COPYRIGHT_HOLDERS" \
    "copyright has Copyright stanza"
assert_contains "$copy_out" "License: $PKG_LICENSE_SPDX" "copyright references SPDX license"
assert_contains "$copy_out" "/usr/share/common-licenses/GPL-3" \
    "GPL-3 license body points at common-licenses, not changelog.gz"
assert_not_contains "$copy_out" "changelog.gz" \
    "copyright must not point license body at changelog.gz"

# With LICENSE present, the body inlines the file (non-GPL path).
PKG_LICENSE_SPDX_ORIG=$PKG_LICENSE_SPDX
PKG_LICENSE_SPDX="MIT"
printf '%s\n' "MIT License" "" "Permission is hereby granted ..." > "$REPO_ROOT/LICENSE"
mit_out=$(_pkg_emit_debian_copyright)
assert_contains "$mit_out" "Permission is hereby granted ..." \
    "non-GPL license body inlined from LICENSE"
PKG_LICENSE_SPDX=$PKG_LICENSE_SPDX_ORIG
rm -rf "$REPO_ROOT"

# --- Finding #4: log / section / run write to stderr ---
log_stdout=$(log "test message" 2>/dev/null)
assert_eq "$log_stdout" "" "log produces no stdout"
log_stderr=$(log "test message" 2>&1 >/dev/null)
assert_contains "$log_stderr" "test message" "log writes to stderr"

section_stdout=$(section "header" 2>/dev/null)
assert_eq "$section_stdout" "" "section produces no stdout"

run_stdout=$(run true 2>/dev/null)
assert_eq "$run_stdout" "" "run produces no stdout for the chatter (command's own stdout still flows)"
run_stderr=$(run true 2>&1 >/dev/null)
assert_contains "$run_stderr" "\$ true" "run echoes the command to stderr"

# --- Finding #7: layout-check.sh has no stray slash-escapes ---
strays=$(grep -nE '\\/' "$FRAMEWORK_HOME/lib/layout-check.sh" || true)
assert_eq "$strays" "" "layout-check.sh contains no \\/ (stray slash escapes)"

# --- Finding #2: workflow template enforces bash for run: blocks ---
# Either a workflow-level defaults.run.shell: bash, or no `source`
# verbs in the template. Both satisfy the contract.
yml="$FRAMEWORK_HOME/lib/pkg-build.yml.tmpl"
if grep -qE '^defaults:' "$yml"; then
    bash_default=$(awk '
        /^defaults:/ { in_defaults=1; next }
        in_defaults && /^[a-zA-Z]/ { in_defaults=0 }
        in_defaults && /shell:[[:space:]]*bash/ { found=1 }
        END { print found+0 }
    ' "$yml")
    assert_eq "$bash_default" "1" "workflow template sets defaults.run.shell: bash"
else
    source_count=$(grep -cE '^\s*source ' "$yml" || true)
    assert_eq "$source_count" "0" "no `source` left without a bash default"
fi

# --- Finding #6: install steps clear doc/man exclusions ---
assert_contains "$(cat "$yml")" "/etc/dpkg/dpkg.cfg.d/excludes" \
    "deb install step removes dpkg doc-excludes"
assert_contains "$(cat "$yml")" "tsflags=nodocs" \
    "rpm install step strips tsflags=nodocs"

# --- Finding #1 (smoke-adjacent): CLI uses readlink -f ---
assert_contains "$(cat "$FRAMEWORK_HOME/bin/pkg-framework")" "readlink -f" \
    "bin/pkg-framework resolves symlinks via readlink -f"

# --- Finding #9: cargo offline knob ---
assert_contains "$(cat "$FRAMEWORK_HOME/lib/framework.sh")" \
    "PKG_CARGO_OFFLINE" \
    "framework.sh honors PKG_CARGO_OFFLINE"
assert_contains "$(cat "$FRAMEWORK_HOME/lib/framework.sh")" \
    "cargo fetch --locked" \
    "PKG_CARGO_OFFLINE path runs cargo fetch --locked"
assert_contains "$(cat "$FRAMEWORK_HOME/lib/framework.sh")" \
    -- "--frozen --offline" \
    "PKG_CARGO_OFFLINE path adds --frozen --offline"

# --- Finding #10: optional per-distro artifact suffix / release tag ---
assert_contains "$(cat "$FRAMEWORK_HOME/lib/framework.sh")" \
    "PKG_DEB_ARTIFACT_SUFFIX" \
    "framework supports PKG_DEB_ARTIFACT_SUFFIX"
assert_contains "$(cat "$FRAMEWORK_HOME/lib/framework.sh")" \
    "PKG_RPM_RELEASE" \
    "framework supports PKG_RPM_RELEASE"

if [[ "${_assert_fail_count:-0}" -gt 0 ]]; then
    printf '\n%d assertion(s) failed in %s\n' "${_assert_fail_count}" "$(basename "$0")" >&2
    exit 1
fi
printf '\nok: all v1.2.2 helper assertions passed\n'
