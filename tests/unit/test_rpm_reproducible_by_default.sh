#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Regression test for v1.4.2: an rpm is the same whichever day it is built.
#
# fpm 1.16.0's rpm backend writes a default %changelog entry dated by the day
# it runs. Unlike its deb backend it never reads SOURCE_DATE_EPOCH, so two
# builds of one commit on either side of midnight UTC differed in the header's
# Changelogtime alone: a consumer's reproducibility (fedora-44) job failed so,
# its first pass built at 23:51 UTC and its second at 00:05. _pkg_fpm_rpm now
# writes the same entry itself, dated by SOURCE_DATE_EPOCH, and passes it with
# --rpm-changelog. rpmbuild also writes the build host and the build time into
# the header, so the framework fixes the one and takes the other, and file
# times, from SOURCE_DATE_EPOCH; a project's own defines come later and win.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A stand-in fpm, first on PATH: it records each argument on its own line,
# keeps a copy of the changelog it is given, and writes the package file.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/fpm" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FPM_ARGS"
prev="" out=""
for a in "$@"; do
    case "$prev" in
        --rpm-changelog) cp "$a" "$FPM_CHANGELOG" ;;
        --package) out=$a ;;
    esac
    prev=$a
done
: > "$out"
SHIM
chmod +x "$TMP/bin/fpm"
export PATH="$TMP/bin:$PATH" FPM_ARGS="$TMP/fpm.args" FPM_CHANGELOG="$TMP/changelog"

# shellcheck disable=SC1091
source "$FRAMEWORK_HOME/lib/framework.sh"

PKG_NAME=demo
PKG_PREFIX=DEMO
PKG_VENDOR="Lou's Clues Labs"
PKG_MAINTAINER="Lou <lou@example.com>"
PKG_SUMMARY="demo package"
PKG_HOMEPAGE_URL="https://example.com/demo"
PKG_SOURCE_URL="https://github.com/lousclues-labs/demo"
PKG_LICENSE_SPDX="GPL-3.0-only"
PKG_LICENSE_NAME="GPL-3.0-only"
PKG_COPYRIGHT_HOLDERS="Lou Junior"
PKG_COPYRIGHT_YEAR="2026"
PKG_DESCRIPTION="A demo package."
PKG_RPM_GROUP="Applications/System"
PKG_DEB_DEPENDS=("libc6 (>= 2.28)")
VERSION="1.2.3"
OUTDIR="$TMP/dist"
STAGE="$TMP/stage"
RPM_OUT="$TMP/rpm-out"
mkdir -p "$OUTDIR" "$STAGE/scripts" "$RPM_OUT"
export PKG_NAME PKG_PREFIX PKG_VENDOR PKG_MAINTAINER PKG_SUMMARY PKG_HOMEPAGE_URL \
    PKG_SOURCE_URL PKG_LICENSE_SPDX PKG_LICENSE_NAME PKG_COPYRIGHT_HOLDERS \
    PKG_COPYRIGHT_YEAR PKG_DESCRIPTION PKG_RPM_GROUP VERSION OUTDIR STAGE RPM_OUT

# Two builds of one commit, a day apart by the wall clock, with one
# SOURCE_DATE_EPOCH: 1700000000 is Tue Nov 14 2023, 22:13:20 UTC.
export SOURCE_DATE_EPOCH=1700000000
_pkg_fpm_rpm >/dev/null 2>&1
first=$(cat "$FPM_CHANGELOG" 2>/dev/null)
passed=$(cat "$FPM_ARGS")

assert_contains "$passed" "--rpm-changelog" "the changelog is the framework's, not fpm's default"
assert_eq "$(head -1 <<<"$first")" \
    "* Tue Nov 14 2023  Lou <lou@example.com> - 1.2.3-1" \
    "the changelog entry is dated by SOURCE_DATE_EPOCH, in fpm's own form"
assert_eq "$(sed -n 2p <<<"$first")" "- Package created with FPM" \
    "the entry's text is fpm's own"
assert_contains "$passed" "_buildhost reproducible" "the build host is fixed"
assert_contains "$passed" "use_source_date_epoch_as_buildtime 1" \
    "the build time is SOURCE_DATE_EPOCH"
assert_contains "$passed" "clamp_mtime_to_source_date_epoch 1" \
    "file times are held to SOURCE_DATE_EPOCH"

# A project's own define comes after the framework's, so it wins.
project_fpm_rpm_extra_args() {
    printf -- '--rpm-rpmbuild-define\n%s\n' '_buildhost project.example'
}
_pkg_fpm_rpm >/dev/null 2>&1
mapfile -t list < "$FPM_ARGS"
last=""
for i in "${!list[@]}"; do
    if [[ "${list[$i]}" == "--rpm-rpmbuild-define" && "${list[$((i + 1))]}" == _buildhost* ]]; then
        last=${list[$((i + 1))]}
    fi
done
assert_eq "$last" "_buildhost project.example" "a project's define is passed last"

assert_done
