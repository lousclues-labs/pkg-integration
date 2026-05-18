#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
#
# Unit tests for _pkg_emit_manifest. Creates a mock artifact, invokes
# the function, and validates the resulting JSON against the schema.

set -uo pipefail
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_assert.sh"

if ! command -v jq >/dev/null 2>&1; then
    printf 'SKIP: jq not installed\n'
    exit 0
fi

# Baseline: a normal manifest emit.
TMP=$(mktemp -d)
artifact="$TMP/demo_1.2.3_amd64.deb"
printf 'fake artifact content' > "$artifact"
expected_sha=$(sha256sum "$artifact" | awk '{print $1}')
expected_size=$(stat -c '%s' "$artifact")

bash -c "
    set -e
    source '$FRAMEWORK_HOME/lib/framework.sh'
    _pkg_compute_paths
    PKG_NAME=demo
    PKG_PREFIX=DEMO
    VERSION=1.2.3
    DISTRO=deb
    SOURCE_DATE_EPOCH=1700000000
    DEMO_MANIFEST_COMMIT=0123456789abcdef0123456789abcdef01234567
    _pkg_emit_manifest '$artifact'
"

manifest="$artifact.manifest.json"
assert_file_exists "$manifest"

actual_schema=$(jq -r .schema "$manifest")
assert_eq "$actual_schema" 'pkg-framework-manifest/1' 'schema field'

actual_sha=$(jq -r .sha256 "$manifest")
assert_eq "$actual_sha" "$expected_sha" 'sha256 matches sha256sum'

actual_size=$(jq -r .size_bytes "$manifest")
assert_eq "$actual_size" "$expected_size" 'size_bytes matches stat'

actual_commit=$(jq -r .source_commit "$manifest")
assert_eq "$actual_commit" '0123456789abcdef0123456789abcdef01234567' 'source_commit echoed'

actual_pkg=$(jq -r .package "$manifest")
assert_eq "$actual_pkg" 'demo' 'package field'

actual_distro=$(jq -r .distro "$manifest")
assert_eq "$actual_distro" 'deb' 'distro field'

# Schema gate (same as workflow uses).
if jq -e '
    .schema == "pkg-framework-manifest/1"
    and (.sha256 | test("^[0-9a-f]{64}$"))
    and (.source_commit | test("^[0-9a-f]{40}$"))
    and (.built_at | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
' "$manifest" >/dev/null; then
    ok 'manifest matches schema gate'
else
    fail 'manifest does not match schema gate'
fi

# unknown commit accepted.
rm -f "$manifest"
bash -c "
    set -e
    source '$FRAMEWORK_HOME/lib/framework.sh'
    _pkg_compute_paths
    PKG_NAME=demo
    PKG_PREFIX=DEMO
    VERSION=1.2.3
    DISTRO=deb
    SOURCE_DATE_EPOCH=1700000000
    _pkg_emit_manifest '$artifact'
"
actual_commit=$(jq -r .source_commit "$manifest")
assert_eq "$actual_commit" 'unknown' 'missing PREFIX_MANIFEST_COMMIT yields unknown'

# malformed commit rejected.
rc=0
bash -c "
    set +e
    source '$FRAMEWORK_HOME/lib/framework.sh' 2>/dev/null
    _pkg_compute_paths
    PKG_NAME=demo
    PKG_PREFIX=DEMO
    VERSION=1.2.3
    DISTRO=deb
    SOURCE_DATE_EPOCH=1700000000
    DEMO_MANIFEST_COMMIT=notavalidhex
    _pkg_emit_manifest '$artifact' >/dev/null 2>&1
    echo \$?
" | { read -r rc; assert_eq "$rc" 2 'malformed commit rejected with rc=2'; }

rm -rf "$TMP"

assert_done
