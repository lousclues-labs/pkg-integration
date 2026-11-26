#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Unit tests for _pkg_validate_env (the per-invocation DISTRO/VERSION/
# OUTDIR check).

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

# Run _pkg_validate_env in a subshell with controlled env.
validate_env_with() {
    local pre=$1
    bash -c "
        set +e
        source '$FRAMEWORK_HOME/lib/framework.sh'
        $pre
        _pkg_validate_env >/dev/null 2>&1
        echo \$?
    "
}

# Baseline: all valid.
rc=$(validate_env_with 'DISTRO=deb VERSION=1.2.3 OUTDIR=/tmp/out')
assert_eq "$rc" 0 'all-valid env passes'

# Missing DISTRO.
rc=$(validate_env_with 'VERSION=1.2.3 OUTDIR=/tmp/out')
assert_eq "$rc" 2 'missing DISTRO rejected'

# Invalid DISTRO.
rc=$(validate_env_with 'DISTRO=tar VERSION=1.2.3 OUTDIR=/tmp/out')
assert_eq "$rc" 2 'invalid DISTRO rejected'

# Missing VERSION.
rc=$(validate_env_with 'DISTRO=deb OUTDIR=/tmp/out')
assert_eq "$rc" 2 'missing VERSION rejected'

# Non-semver VERSION.
rc=$(validate_env_with 'DISTRO=deb VERSION=v1 OUTDIR=/tmp/out')
assert_eq "$rc" 2 'non-semver VERSION rejected'

# Pre-release semver.
rc=$(validate_env_with 'DISTRO=deb VERSION=1.2.3-rc1 OUTDIR=/tmp/out')
assert_eq "$rc" 0 'pre-release semver accepted'

# Build-metadata semver.
rc=$(validate_env_with 'DISTRO=deb VERSION=1.2.3+build4 OUTDIR=/tmp/out')
assert_eq "$rc" 0 'build-metadata semver accepted'

rc=$(validate_env_with 'DISTRO=deb VERSION=1.2.3~rc.1 OUTDIR=/tmp/out')
assert_eq "$rc" 2 'Debian candidate requires opt-in'

rc=$(validate_env_with 'PKG_DEB_BUILD_VERSION=1 DISTRO=deb VERSION=1.2.3~rc.1 OUTDIR=/tmp/out')
assert_eq "$rc" 0 'Debian candidate accepted with opt-in'

rc=$(validate_env_with 'PKG_DEB_BUILD_VERSION=1 DISTRO=deb VERSION=1.2.3+100.g1a2b3c4 OUTDIR=/tmp/out')
assert_eq "$rc" 0 'identified Debian snapshot accepted with opt-in'

rc=$(validate_env_with 'PKG_DEB_BUILD_VERSION=1 DISTRO=deb VERSION=1.2.3-rc.1 OUTDIR=/tmp/out')
assert_eq "$rc" 2 'candidate cannot sort after the final Debian version'

rc=$(validate_env_with 'PKG_DEB_BUILD_VERSION=1 DISTRO=deb VERSION=1.2.3+100.gabcdefg OUTDIR=/tmp/out')
assert_eq "$rc" 2 'malformed snapshot commit refused'

rc=$(validate_env_with 'PKG_DEB_BUILD_VERSION=1 DISTRO=rpm VERSION=1.2.3~rc.1 OUTDIR=/tmp/out')
assert_eq "$rc" 2 'Debian opt-in does not extend RPM syntax'

cargo_dir=$(mktemp -d)
trap 'rm -rf "$cargo_dir"' EXIT
printf '[package]\nversion = "1.2.3"\n' > "$cargo_dir/Cargo.toml"

cargo_match() {
    bash -c '
        source "$FRAMEWORK_HOME/lib/framework.sh"
        REPO_ROOT=$1 DISTRO=$2 VERSION=$3 PKG_DEB_BUILD_VERSION=$4
        _pkg_validate_version_matches_cargo
    ' cargo-match "$cargo_dir" "$@" >/dev/null 2>&1
}

assert_rc 0 cargo_match deb '1.2.3~rc.1' 1
assert_rc 0 cargo_match deb '1.2.3+100.g1a2b3c4' 1
assert_rc 0 cargo_match deb '1.2.3' 1
assert_rc 2 cargo_match deb '1.2.4~rc.1' 1
assert_rc 2 cargo_match deb '1.2.3+100.g1a2b3c4' 0
assert_rc 2 cargo_match rpm '1.2.3+100.g1a2b3c4' 1

# Missing OUTDIR.
rc=$(validate_env_with 'DISTRO=deb VERSION=1.2.3')
assert_eq "$rc" 2 'missing OUTDIR rejected'

# Relative OUTDIR.
rc=$(validate_env_with 'DISTRO=deb VERSION=1.2.3 OUTDIR=./out')
assert_eq "$rc" 2 'relative OUTDIR rejected'

assert_done
