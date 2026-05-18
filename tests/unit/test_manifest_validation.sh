#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Unit tests for _pkg_validate_manifest. Each test invokes the
# validator in a clean subshell with a minimal manifest, varying one
# field at a time to confirm pass/fail behavior.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

# Run _pkg_validate_manifest in a subshell with controlled env. Echoes
# the rc and any stderr output combined.
validate_with() {
    local script=$1
    bash -c "
        set +e
        source '$FRAMEWORK_HOME/lib/framework.sh'
        $script
        _pkg_validate_manifest >/dev/null 2>&1
        echo \$?
    "
}

# Baseline: minimal complete manifest passes.
rc=$(validate_with '
    PKG_NAME=demo
    PKG_PREFIX=DEMO
    PKG_SUMMARY="x"
    PKG_DESCRIPTION="x"
    PKG_VENDOR="x"
    PKG_MAINTAINER="x"
    PKG_HOMEPAGE_URL="https://x"
    PKG_SOURCE_URL="https://x"
    PKG_LICENSE_SPDX="GPL-3.0-only"
    PKG_LICENSE_NAME="GPL-3.0-only"
    PKG_COPYRIGHT_HOLDERS="x"
    PKG_COPYRIGHT_YEAR="2025"
    PKG_BINARIES=(demo)
    PKG_DEB_DEPENDS=("libc6")
')
assert_eq "$rc" 0 'minimal complete manifest passes'

# Missing PKG_NAME.
rc=$(validate_with '
    PKG_PREFIX=DEMO
    PKG_SUMMARY="x"
    PKG_DESCRIPTION="x"
    PKG_VENDOR="x"
    PKG_MAINTAINER="x"
    PKG_HOMEPAGE_URL="https://x"
    PKG_SOURCE_URL="https://x"
    PKG_LICENSE_SPDX="x"
    PKG_LICENSE_NAME="x"
    PKG_COPYRIGHT_HOLDERS="x"
    PKG_COPYRIGHT_YEAR="2025"
    PKG_BINARIES=(demo)
    PKG_DEB_DEPENDS=("libc6")
')
assert_eq "$rc" 2 'missing PKG_NAME rejected'

# Invalid PKG_NAME (uppercase).
rc=$(validate_with '
    PKG_NAME=Demo
    PKG_PREFIX=DEMO
    PKG_SUMMARY="x"
    PKG_DESCRIPTION="x"
    PKG_VENDOR="x"
    PKG_MAINTAINER="x"
    PKG_HOMEPAGE_URL="https://x"
    PKG_SOURCE_URL="https://x"
    PKG_LICENSE_SPDX="x"
    PKG_LICENSE_NAME="x"
    PKG_COPYRIGHT_HOLDERS="x"
    PKG_COPYRIGHT_YEAR="2025"
    PKG_BINARIES=(demo)
    PKG_DEB_DEPENDS=("libc6")
')
assert_eq "$rc" 2 'PKG_NAME with uppercase rejected'

# Invalid PKG_PREFIX (lowercase).
rc=$(validate_with '
    PKG_NAME=demo
    PKG_PREFIX=demo
    PKG_SUMMARY="x"
    PKG_DESCRIPTION="x"
    PKG_VENDOR="x"
    PKG_MAINTAINER="x"
    PKG_HOMEPAGE_URL="https://x"
    PKG_SOURCE_URL="https://x"
    PKG_LICENSE_SPDX="x"
    PKG_LICENSE_NAME="x"
    PKG_COPYRIGHT_HOLDERS="x"
    PKG_COPYRIGHT_YEAR="2025"
    PKG_BINARIES=(demo)
    PKG_DEB_DEPENDS=("libc6")
')
assert_eq "$rc" 2 'PKG_PREFIX with lowercase rejected'

# Empty PKG_BINARIES.
rc=$(validate_with '
    PKG_NAME=demo
    PKG_PREFIX=DEMO
    PKG_SUMMARY="x"
    PKG_DESCRIPTION="x"
    PKG_VENDOR="x"
    PKG_MAINTAINER="x"
    PKG_HOMEPAGE_URL="https://x"
    PKG_SOURCE_URL="https://x"
    PKG_LICENSE_SPDX="x"
    PKG_LICENSE_NAME="x"
    PKG_COPYRIGHT_HOLDERS="x"
    PKG_COPYRIGHT_YEAR="2025"
    PKG_BINARIES=()
    PKG_DEB_DEPENDS=("libc6")
')
assert_eq "$rc" 2 'empty PKG_BINARIES rejected'

assert_done
