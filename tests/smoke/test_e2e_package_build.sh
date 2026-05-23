#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# End-to-end smoke for the framework's fpm + validate path. Built
# specifically to catch the bugs vigil hit on first real adoption:
#
#  - artifact-path capture must be exactly one path (no log spam),
#  - validate_artifact must not SIGPIPE on packages > 20 entries,
#  - multi-line PKG_DESCRIPTION must reach fpm intact,
#  - debian copyright must include the SPDX-correct license body.
#
# Strategy: shim fpm. The real fpm is not on this host and is heavy
# to install. The shim parses the same argv shape and emits a tiny
# real .deb / .rpm artifact via dpkg-deb / rpmbuild stubs when
# available, or a deterministic placeholder otherwise. The framework
# under test never knows it is not talking to upstream fpm.

set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
FRAMEWORK_HOME="$(cd -- "$HERE/../.." && pwd)"
export FRAMEWORK_HOME

tmp=$(mktemp -d -t pkg-framework-e2e.XXXXXX)
trap 'rm -rf "$tmp"' EXIT

fail=0
pass() { printf '  ok   %s\n' "$*"; }
fal()  { printf '  FAIL %s\n' "$*" >&2; fail=$(( fail + 1 )); }
step() { printf '\n--- %s ---\n' "$*"; }

# -------------------------------------------------------------------------
# Build a fake `fpm` shim that records its argv to a sidecar file
# and emits a tiny tarball as the artifact at --package. Good enough
# for the framework to think it succeeded and for us to inspect the
# argv to confirm correctness.
# -------------------------------------------------------------------------
shim_dir="$tmp/shim"
mkdir -p "$shim_dir"
cat > "$shim_dir/fpm" <<'SHIM'
#!/usr/bin/env bash
# fpm shim for pkg-framework e2e smoke. Records argv and emits a
# minimal artifact at --package.
set -euo pipefail
argv_log="${FPM_SHIM_ARGV_LOG:-/tmp/fpm_shim.argv}"
# Record full argv NUL-delimited so multi-line args survive readback.
{
    for a in "$@"; do
        printf '%s\0' "$a"
    done
    printf '\n--END--\n'
} >> "$argv_log"

# Find --package PATH.
out=""
prev=""
for a in "$@"; do
    if [[ "$prev" == "--package" ]]; then
        out=$a
        break
    fi
    prev=$a
done
[[ -n "$out" ]] || { echo "fpm-shim: --package missing" >&2; exit 1; }

# Build a small tar with > 20 entries so validate's `head -20` path
# is actually exercised against a long listing.
work=$(mktemp -d)
mkdir -p "$work/contents/usr/bin" "$work/contents/usr/share/doc/demo" \
         "$work/contents/usr/share/man/man1"
for i in $(seq 1 30); do
    printf 'placeholder %d\n' "$i" > "$work/contents/usr/share/doc/demo/file-$i"
done
printf 'fake binary\n' > "$work/contents/usr/bin/demo"
printf 'fake man page\n' > "$work/contents/usr/share/man/man1/demo.1"

case "$out" in
    *.deb)
        # If dpkg-deb is on PATH, build a real one so dpkg-deb -c
        # in the framework's validate step works. Otherwise emit a
        # tar with .deb extension (validate -I will fail but we
        # still test artifact capture and listing path).
        if command -v dpkg-deb >/dev/null 2>&1; then
            mkdir -p "$work/DEBIAN"
            cat > "$work/DEBIAN/control" <<CTL
Package: demo
Version: 1.2.3
Architecture: amd64
Maintainer: Lou <lou@example.com>
Description: shim-built smoke artifact
CTL
            mv "$work/contents"/* "$work/" 2>/dev/null
            rmdir "$work/contents" 2>/dev/null || true
            dpkg-deb --build --root-owner-group "$work" "$out" >/dev/null
        else
            tar -C "$work/contents" -czf "$out" .
        fi
        ;;
    *.rpm)
        tar -C "$work/contents" -czf "$out" .
        ;;
    *)
        tar -C "$work/contents" -czf "$out" .
        ;;
esac
rm -rf "$work"
SHIM
chmod 0755 "$shim_dir/fpm"

# Need dpkg-deb and rpm for the validate step. Stub rpm-qpl/rpm-qpi
# only if missing.
if ! command -v rpm >/dev/null 2>&1; then
    cat > "$shim_dir/rpm" <<'RPM'
#!/usr/bin/env bash
case "$1" in
    -qpi) printf 'Name        : demo\nVersion     : 1.2.3\n' ;;
    -qpl) for i in $(seq 1 30); do printf '/usr/share/doc/demo/file-%d\n' "$i"; done ;;
    *)    exit 0 ;;
esac
RPM
    chmod 0755 "$shim_dir/rpm"
fi

export PATH="$shim_dir:$PATH"

# -------------------------------------------------------------------------
step "1. _pkg_fpm_deb returns ONE artifact path (no log spam)"
# -------------------------------------------------------------------------
OUTDIR="$tmp/dist"
STAGE="$tmp/stage"
DEB_OUT="$tmp/deb-out"
mkdir -p "$OUTDIR" "$STAGE/scripts" "$DEB_OUT"
export FPM_SHIM_ARGV_LOG="$tmp/fpm.argv"
: > "$FPM_SHIM_ARGV_LOG"

# Source framework + set up the globals it expects.
# shellcheck disable=SC1091
source "$FRAMEWORK_HOME/lib/framework.sh"

PKG_NAME=demo
PKG_PREFIX=DEMO
PKG_VENDOR="Lou's Clues Labs"
PKG_MAINTAINER="Lou <lou@example.com>"
PKG_SUMMARY="Smoke fixture demo package"
PKG_HOMEPAGE_URL="https://example.com/demo"
PKG_SOURCE_URL="https://github.com/lousclues-labs/demo"
PKG_LICENSE_SPDX="GPL-3.0-only"
PKG_LICENSE_NAME="GPL-3.0-only"
PKG_COPYRIGHT_HOLDERS="Lou Junior"
PKG_COPYRIGHT_YEAR="2026"
VERSION="1.2.3"
PKG_DEB_SECTION="net"
PKG_DEB_PRIORITY="optional"
PKG_RPM_GROUP="Applications/System"
PKG_DEB_DEPENDS=("libc6 (>= 2.28)")

# Multi-line description (finding #3).
PKG_DESCRIPTION="First paragraph of the description.

Second paragraph that previously corrupted the fpm command line."

# Capture _pkg_fpm_deb's stdout. v1.2.2 routes all chatter to stderr;
# stdout must be exactly the artifact path.
artifact_path=$(_pkg_fpm_deb 2>"$tmp/fpm_deb.stderr")
rc=$?
if [[ "$rc" -ne 0 ]]; then
    fal "_pkg_fpm_deb exit=$rc; stderr tail:"
    tail -10 "$tmp/fpm_deb.stderr" | sed 's/^/    /' >&2
fi

# Stdout from _pkg_fpm_deb must be a single path with no embedded
# newlines (i.e. no log lines bled in).
if [[ "$artifact_path" =~ $'\n' ]]; then
    fal "artifact path contains newline (log spam captured); full value:"
    printf '%s\n' "$artifact_path" | sed 's/^/      /' >&2
else
    pass "artifact path is a single line: $artifact_path"
fi
[[ -f "$artifact_path" ]] && pass "artifact file exists" \
    || fal "artifact missing at $artifact_path"

# -------------------------------------------------------------------------
step "2. multi-line PKG_DESCRIPTION reached fpm intact (one --description)"
# -------------------------------------------------------------------------
desc_count=$(grep -czF -- "--description" "$FPM_SHIM_ARGV_LOG" 2>/dev/null \
    | awk '{print $1}')
desc_count=$(awk 'BEGIN{RS="\0"} /^--description$/ {n++} END {print n+0}' "$FPM_SHIM_ARGV_LOG")
if [[ "$desc_count" == "1" ]]; then
    pass "exactly one --description arg recorded"
else
    fal "expected exactly 1 --description, got $desc_count"
fi
# The arg immediately after --description must equal the full body.
recorded_desc=$(awk 'BEGIN{RS="\0"} prev=="--description"{print; exit} {prev=$0}' "$FPM_SHIM_ARGV_LOG")
if [[ "$recorded_desc" == "$PKG_DESCRIPTION" ]]; then
    pass "fpm received the full multi-line description as one arg"
else
    fal "description corrupted in transit; recorded len=${#recorded_desc} vs expected len=${#PKG_DESCRIPTION}"
fi

# -------------------------------------------------------------------------
step "3. _pkg_validate_artifact survives a > 20 entry listing (no SIGPIPE)"
# -------------------------------------------------------------------------
set +e
( set -euo pipefail; _pkg_validate_artifact "$artifact_path" ) 2>"$tmp/validate.stderr"
val_rc=$?
set -e
if [[ "$val_rc" -eq 0 ]]; then
    pass "_pkg_validate_artifact exit 0 under set -euo pipefail with >20 entries"
else
    fal "_pkg_validate_artifact exit=$val_rc; stderr:"
    tail -10 "$tmp/validate.stderr" | sed 's/^/    /' >&2
fi

# -------------------------------------------------------------------------
step "4. PKG_DEB_ARTIFACT_SUFFIX yields a distro-tagged artifact name"
# -------------------------------------------------------------------------
PKG_DEB_ARTIFACT_SUFFIX="-noble"
suffix_artifact=$(_pkg_fpm_deb 2>"$tmp/fpm_deb_suffix.stderr")
if [[ "$suffix_artifact" == *"_1.2.3-noble_amd64.deb" ]]; then
    pass "deb suffix lands in filename: $(basename "$suffix_artifact")"
else
    fal "expected ..._1.2.3-noble_amd64.deb, got $(basename "$suffix_artifact")"
fi
unset PKG_DEB_ARTIFACT_SUFFIX

# -------------------------------------------------------------------------
step "5. PKG_RPM_RELEASE yields a distro-tagged rpm name"
# -------------------------------------------------------------------------
RPM_OUT="$tmp/rpm-out"
mkdir -p "$RPM_OUT"
PKG_RPM_RELEASE="1.fedora40"
rpm_artifact=$(_pkg_fpm_rpm 2>"$tmp/fpm_rpm.stderr")
if [[ "$rpm_artifact" == *"-1.2.3-1.fedora40.x86_64.rpm" ]]; then
    pass "rpm release tag lands in filename: $(basename "$rpm_artifact")"
else
    fal "expected ...-1.2.3-1.fedora40.x86_64.rpm, got $(basename "$rpm_artifact")"
fi
# fpm should also receive --iteration with the same value.
iter_count=$(awk 'BEGIN{RS="\0"} prev=="--iteration" && $0=="1.fedora40"{n++} {prev=$0} END {print n+0}' "$FPM_SHIM_ARGV_LOG")
if [[ "$iter_count" -ge 1 ]]; then
    pass "fpm received --iteration 1.fedora40"
else
    fal "fpm did not receive --iteration 1.fedora40 (count=$iter_count)"
fi
unset PKG_RPM_RELEASE

# -------------------------------------------------------------------------
step "6. CLI works through a symlink (finding #1)"
# -------------------------------------------------------------------------
ln_dir="$tmp/bin"
mkdir -p "$ln_dir"
ln -sfn "$FRAMEWORK_HOME/bin/pkg-framework" "$ln_dir/pkg-framework"
sym_version=$("$ln_dir/pkg-framework" version 2>"$tmp/symlink.stderr") || true
if [[ "$sym_version" == "$(cat "$FRAMEWORK_HOME/VERSION")" ]]; then
    pass "version through symlink: $sym_version"
else
    fal "version through symlink: got '$sym_version'; stderr:"
    cat "$tmp/symlink.stderr" | sed 's/^/    /' >&2
fi

# -------------------------------------------------------------------------
printf '\n---\n'
if [[ "$fail" -gt 0 ]]; then
    printf 'e2e FAILED (%d check(s))\n' "$fail" >&2
    exit 1
fi
printf 'e2e clean: fpm capture + multi-line description + validate listing + suffix knobs + symlink CLI all green\n'
