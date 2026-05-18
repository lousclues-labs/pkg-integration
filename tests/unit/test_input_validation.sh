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

# Missing OUTDIR.
rc=$(validate_env_with 'DISTRO=deb VERSION=1.2.3')
assert_eq "$rc" 2 'missing OUTDIR rejected'

# Relative OUTDIR.
rc=$(validate_env_with 'DISTRO=deb VERSION=1.2.3 OUTDIR=./out')
assert_eq "$rc" 2 'relative OUTDIR rejected'

assert_done
