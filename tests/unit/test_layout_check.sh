#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Unit tests for layout-check.sh. Builds a fake installed-tree under
# $ROOT, points layout-check.sh at it via $PROJECT_SH + $ROOT env vars,
# and asserts pass / fail for each scenario.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

LAYOUT_CHECK="$FRAMEWORK_HOME/lib/layout-check.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Write a minimal project.sh for the fake stage.
write_project_sh() {
    local out=$1
    cat > "$out" <<'EOF'
PKG_NAME=demo
PKG_PREFIX=DEMO
PKG_BINARIES=(demo)
PKG_LAYOUT_CHECKS=(
    "usr/bin/demo:755"
    "etc/demo/demo.conf:644"
)
PKG_SYSTEMD_UNITS=(demo.service)
EOF
}

# Build a stage tree that satisfies all checks.
make_complete_stage() {
    local root=$1
    install -D -m 0755 /dev/null "$root/usr/bin/demo"
    install -d -m 0755 "$root/usr/share/doc/demo"
    echo readme > "$root/usr/share/doc/demo/README.md"
    gzip -n < "$root/usr/share/doc/demo/README.md" > "$root/usr/share/doc/demo/changelog.gz"
    install -D -m 0644 /dev/null "$root/usr/share/doc/demo/copyright"
    install -D -m 0644 /dev/null "$root/etc/demo/demo.conf"
    install -d -m 0755 "$root/lib/systemd/system"
    cat > "$root/lib/systemd/system/demo.service" <<'UNIT'
[Unit]
Description=demo

[Service]
ExecStart=/usr/bin/demo

[Install]
WantedBy=multi-user.target
UNIT
    chmod 0644 "$root/lib/systemd/system/demo.service"
}

run_layout_check() {
    local root=$1 proj=$2 ext=${3:-deb}
    PROJECT_SH="$proj" ROOT="$root" EXT="$ext" bash "$LAYOUT_CHECK"
}

# Case 1: complete stage tree passes.
ROOT_OK="$TMP/ok"
PROJ_OK="$TMP/project-ok.sh"
mkdir -p "$ROOT_OK"
write_project_sh "$PROJ_OK"
make_complete_stage "$ROOT_OK"
if run_layout_check "$ROOT_OK" "$PROJ_OK" deb >/dev/null 2>&1; then
    ok 'complete stage passes layout-check'
else
    fail 'complete stage should pass but layout-check returned non-zero'
fi

# Case 2: missing binary -> fail.
ROOT_NOBIN="$TMP/nobin"
mkdir -p "$ROOT_NOBIN"
make_complete_stage "$ROOT_NOBIN"
rm -f "$ROOT_NOBIN/usr/bin/demo"
if run_layout_check "$ROOT_NOBIN" "$PROJ_OK" deb >/dev/null 2>&1; then
    fail 'missing binary should fail'
else
    ok 'missing binary failed as expected'
fi

# Case 3: wrong mode on layout entry -> fail.
ROOT_BADMODE="$TMP/badmode"
mkdir -p "$ROOT_BADMODE"
make_complete_stage "$ROOT_BADMODE"
chmod 0600 "$ROOT_BADMODE/etc/demo/demo.conf"
out=$(run_layout_check "$ROOT_BADMODE" "$PROJ_OK" deb 2>&1) && rc=0 || rc=$?
assert_neq "$rc" 0 'wrong-mode layout entry yields non-zero rc'
assert_contains "$out" 'mode 600, expected 644' 'reports actual+expected mode'

# Case 4: missing systemd unit -> fail.
ROOT_NOUNIT="$TMP/nounit"
mkdir -p "$ROOT_NOUNIT"
make_complete_stage "$ROOT_NOUNIT"
rm -f "$ROOT_NOUNIT/lib/systemd/system/demo.service"
if run_layout_check "$ROOT_NOUNIT" "$PROJ_OK" deb >/dev/null 2>&1; then
    fail 'missing systemd unit should fail'
else
    ok 'missing systemd unit failed as expected'
fi

# Case 5: ExecStart pointing into /home -> fail (dev-path regression).
ROOT_DEVPATH="$TMP/devpath"
mkdir -p "$ROOT_DEVPATH"
make_complete_stage "$ROOT_DEVPATH"
cat > "$ROOT_DEVPATH/lib/systemd/system/demo.service" <<'UNIT'
[Unit]
Description=demo

[Service]
ExecStart=/home/dev/target/release/demo

[Install]
WantedBy=multi-user.target
UNIT
out=$(run_layout_check "$ROOT_DEVPATH" "$PROJ_OK" deb 2>&1) && rc=0 || rc=$?
assert_neq "$rc" 0 'dev-path ExecStart yields non-zero rc'
assert_contains "$out" 'dev path in ExecStart' 'reports dev-path regression'

# Case 6: missing copyright (deb) -> fail.
ROOT_NOCR="$TMP/nocr"
mkdir -p "$ROOT_NOCR"
make_complete_stage "$ROOT_NOCR"
rm -f "$ROOT_NOCR/usr/share/doc/demo/copyright"
if run_layout_check "$ROOT_NOCR" "$PROJ_OK" deb >/dev/null 2>&1; then
    fail 'missing deb copyright should fail'
else
    ok 'missing deb copyright failed as expected'
fi

assert_done
