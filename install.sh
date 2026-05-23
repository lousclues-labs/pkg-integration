#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-3.0-only
#
# pkg-framework one-line installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/lousclues-labs/pkg-integration/main/install.sh | sh
#   PKG_FRAMEWORK_REF=v1.2.0 curl ... | sh
#
# What it does:
#   1. Clones (or fetches) lousclues-labs/pkg-integration into
#      ${PKG_FRAMEWORK_HOME:-$HOME/.local/share/pkg-framework}.
#   2. Checks out ${PKG_FRAMEWORK_REF:-main}.
#   3. Symlinks the cli into ${PKG_FRAMEWORK_BIN:-$HOME/.local/bin}.
#   4. Prints the next two commands to run.
#
# Idempotent: re-running upgrades the checkout to the requested ref
# and refreshes the symlink. Never touches a project's pkg/ tree.
#
# POSIX sh on purpose. No bashisms; runs on Alpine, macOS, BSD.

set -eu

PKG_FRAMEWORK_REMOTE="${PKG_FRAMEWORK_REMOTE:-https://github.com/lousclues-labs/pkg-integration.git}"
PKG_FRAMEWORK_HOME="${PKG_FRAMEWORK_HOME:-$HOME/.local/share/pkg-framework}"
PKG_FRAMEWORK_BIN="${PKG_FRAMEWORK_BIN:-$HOME/.local/bin}"
PKG_FRAMEWORK_REF="${PKG_FRAMEWORK_REF:-main}"

say() { printf 'install: %s\n' "$*"; }
die() { printf 'install: error: %s\n' "$*" >&2; exit 1; }

# Preflight.
command -v git  >/dev/null 2>&1 || die "git not on PATH"
command -v ln   >/dev/null 2>&1 || die "ln not on PATH"
mkdir -p "$PKG_FRAMEWORK_BIN" || die "cannot create $PKG_FRAMEWORK_BIN"

if [ -d "$PKG_FRAMEWORK_HOME/.git" ]; then
    say "updating existing checkout at $PKG_FRAMEWORK_HOME"
    git -C "$PKG_FRAMEWORK_HOME" fetch --tags --quiet origin
    git -C "$PKG_FRAMEWORK_HOME" checkout --quiet "$PKG_FRAMEWORK_REF"
    # Only fast-forward branches; tags are detached and stay put.
    if git -C "$PKG_FRAMEWORK_HOME" symbolic-ref -q HEAD >/dev/null; then
        git -C "$PKG_FRAMEWORK_HOME" pull --ff-only --quiet
    fi
else
    say "cloning into $PKG_FRAMEWORK_HOME"
    mkdir -p "$(dirname "$PKG_FRAMEWORK_HOME")"
    git clone --quiet "$PKG_FRAMEWORK_REMOTE" "$PKG_FRAMEWORK_HOME"
    git -C "$PKG_FRAMEWORK_HOME" checkout --quiet "$PKG_FRAMEWORK_REF"
fi

cli="$PKG_FRAMEWORK_HOME/bin/pkg-framework"
[ -x "$cli" ] || die "cli not executable at $cli (checkout broken?)"

link="$PKG_FRAMEWORK_BIN/pkg-framework"
ln -sfn "$cli" "$link"
say "symlinked $link -> $cli"

installed_version=$(tr -d '\r\n' < "$PKG_FRAMEWORK_HOME/VERSION" 2>/dev/null || echo "?")
say "pkg-framework $installed_version installed (ref: $PKG_FRAMEWORK_REF)"

# Friendly nudge if the bin dir isn't on PATH.
case ":$PATH:" in
    *":$PKG_FRAMEWORK_BIN:"*) : ;;
    *)
        printf '\n'
        printf 'note: %s is not on your PATH. Add this to ~/.bashrc or ~/.zshrc:\n' "$PKG_FRAMEWORK_BIN"
        printf '\n    export PATH="%s:$PATH"\n\n' "$PKG_FRAMEWORK_BIN"
        ;;
esac

cat <<EOF

next:
  pkg-framework doctor                       # confirm tools on PATH
  cd /path/to/my-rust-project
  pkg-framework init                         # interactive scaffold

upgrade later: re-run this installer, or:
  pkg-framework upgrade
EOF
