#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Regression test for v1.3.1: _pkg_validate_artifact prints the head of
# an artifact's file listing without a pipe, so a long listing cannot
# fail a valid build under set -o pipefail.
#
# v1.2.2 captured the listing into a variable and then ran
# `printf '%s\n' "$listing" | head -20`. A listing longer than the pipe's
# buffer is written in more than one write; head exits after twenty
# lines, and printf dies of SIGPIPE (exit 141). A consumer's
# reproducibility job failed so on a package its first pass had built
# and checked. The listings here are far longer than any pipe buffer, so
# the old line fails every time (the counter-check below), not by chance.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"
# shellcheck disable=SC1091
source "$FRAMEWORK_HOME/lib/framework.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
LINES=200000

# Stand-ins for dpkg-deb and rpm, first on PATH: an info block, and a
# listing of $LINES entries.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/dpkg-deb" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -I) printf ' Package: stand-in\n' ;;
    -c) seq -f './usr/share/stand-in/entry-%g' 1 "$LISTING_LINES" ;;
    *) exit 2 ;;
esac
EOF
cat > "$TMP/bin/rpm" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -qpi) printf 'Name        : stand-in\n' ;;
    -qpl) seq -f '/usr/share/stand-in/entry-%g' 1 "$LISTING_LINES" ;;
    *) exit 2 ;;
esac
EOF
chmod 0755 "$TMP/bin/dpkg-deb" "$TMP/bin/rpm"
export LISTING_LINES=$LINES
PATH="$TMP/bin:$PATH"

printf 'not empty\n' > "$TMP/stand-in.deb"
printf 'not empty\n' > "$TMP/stand-in.rpm"

# --- a long listing passes, five times for each kind ---
for kind in deb rpm; do
    for attempt in 1 2 3 4 5; do
        ( set -euo pipefail; _pkg_validate_artifact "$TMP/stand-in.$kind" ) \
            > /dev/null 2> "$TMP/err"
        rc=$?
        assert_eq "$rc" 0 "$kind listing of $LINES entries passes (attempt $attempt)"
    done
    err=$(cat "$TMP/err")
    assert_contains "$err" "entry-20" "$kind: the twentieth entry is printed"
    assert_not_contains "$err" "entry-21" "$kind: the twenty-first is not"
done

# --- a missing artifact still fails ---
( set -euo pipefail; _pkg_validate_artifact "$TMP/absent.deb" ) > /dev/null 2>&1
assert_eq "$?" 1 "a missing artifact fails"

# --- the counter-check: the v1.2.2 line fails on the same listing ---
listing=$(seq -f './usr/share/stand-in/entry-%g' 1 "$LINES")
( set -o pipefail; printf '%s\n' "$listing" | head -20 > /dev/null )
rc=$?
assert_neq "$rc" 0 "printf | head of the same listing fails under pipefail (rc $rc)"
# shellcheck disable=SC2016
if grep -q 'printf .%s\\n. "$listing" | head' "$FRAMEWORK_HOME/lib/framework.sh"; then
    fail "framework.sh still pipes the listing into head"
else
    ok "framework.sh no longer pipes the listing into head"
fi

assert_done
