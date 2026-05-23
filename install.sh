#!/usr/bin/env sh
# SPDX-License-Identifier: GPL-3.0-only
#
# pkg-framework one-line installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/lousclues-labs/pkg-integration/main/install.sh | sh
#   PKG_FRAMEWORK_REF=v1.2.0 curl ... | sh
#   PKG_FRAMEWORK_METHOD=git curl ... | sh    # force git path
#
# v1.2.1 hardening:
#   - Default ref is the latest published release tag, NOT main.
#     Resolves via `git ls-remote --tags --sort=-v:refname`. A
#     curl|sh installer that defaults to a moving branch is a
#     textbook supply-chain footgun.
#   - When the requested ref is a vN tag and curl + sha256sum are
#     present, the installer downloads the published tarball, verifies
#     its sha256 against the sidecar from the same release, and
#     extracts. The release pipeline produces both files; this closes
#     the loop between "we sign with sha256" and "consumers verify".
#   - Falls back to `git clone` when the tarball path is not viable
#     (no curl, no sha256sum, ref is a branch, or release tarball
#     not yet published for that tag).
#
# What it does:
#   1. Resolves PKG_FRAMEWORK_REF (default: latest vN tag from the
#      remote). main is allowed but no longer the default.
#   2. Either downloads + verifies the release tarball OR clones
#      via git, depending on tool availability and ref shape.
#   3. Symlinks the cli into ${PKG_FRAMEWORK_BIN:-$HOME/.local/bin}.
#   4. Prints the next two commands.
#
# Idempotent: re-running with a different ref upgrades the install.
#
# POSIX sh on purpose. No bashisms; runs on Alpine, macOS, BSD.

set -eu

PKG_FRAMEWORK_OWNER="${PKG_FRAMEWORK_OWNER:-lousclues-labs}"
PKG_FRAMEWORK_REPO="${PKG_FRAMEWORK_REPO:-pkg-integration}"
PKG_FRAMEWORK_REMOTE="${PKG_FRAMEWORK_REMOTE:-https://github.com/${PKG_FRAMEWORK_OWNER}/${PKG_FRAMEWORK_REPO}.git}"
PKG_FRAMEWORK_HOME="${PKG_FRAMEWORK_HOME:-$HOME/.local/share/pkg-framework}"
PKG_FRAMEWORK_BIN="${PKG_FRAMEWORK_BIN:-$HOME/.local/bin}"
PKG_FRAMEWORK_METHOD="${PKG_FRAMEWORK_METHOD:-auto}"     # auto | tarball | git
PKG_FRAMEWORK_REF="${PKG_FRAMEWORK_REF:-}"

say() { printf 'install: %s\n' "$*"; }
die() { printf 'install: error: %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Resolve the default ref to the latest published vN tag from the
# remote. We deliberately do not default to main: a tagged release
# is something the maintainer has stood behind and signed; main is
# whatever happened to land most recently. The release pipeline
# publishes a vN tag for every release.
resolve_default_ref() {
    have git || return 1
    git ls-remote --tags --refs --sort=-v:refname \
        "$PKG_FRAMEWORK_REMOTE" 'v*' 2>/dev/null \
        | head -1 \
        | sed -E 's@^[a-f0-9]+\trefs/tags/@@'
}

# Returns 0 if $1 looks like a release tag (vN.N.N), 1 otherwise.
is_release_tag() {
    case "$1" in
        v[0-9]*.[0-9]*.[0-9]*|v[0-9]*.[0-9]*) return 0 ;;
        *) return 1 ;;
    esac
}

# Tarball path: download + verify sha256 + extract. Only used when
# the ref is a release tag and the tools are present. Returns 0 on
# success; non-zero if the tarball is unavailable or verification
# fails (caller falls back to git).
install_via_tarball() {
    ref=$1
    have curl     || return 1
    have sha256sum || return 1
    have tar      || return 1

    tarball="pkg-framework-${ref}.tar.gz"
    base="https://github.com/${PKG_FRAMEWORK_OWNER}/${PKG_FRAMEWORK_REPO}/releases/download/${ref}"
    tarball_url="${base}/${tarball}"
    sha_url="${tarball_url}.sha256"

    workdir=$(mktemp -d 2>/dev/null) || return 1
    # POSIX sh has no trap-on-return; rely on the early-return path
    # rm and the final-success rm.
    say "fetching $tarball_url"
    if ! curl -fsSL "$tarball_url" -o "$workdir/$tarball"; then
        rm -rf "$workdir"
        return 1
    fi
    say "fetching $sha_url"
    if ! curl -fsSL "$sha_url" -o "$workdir/$tarball.sha256"; then
        rm -rf "$workdir"
        return 1
    fi

    say "verifying sha256"
    # The sidecar format is "<sha256>  <filename>". sha256sum -c
    # checks both. Run from workdir so the embedded filename matches.
    if ! (cd "$workdir" && sha256sum -c "$tarball.sha256" >/dev/null 2>&1); then
        printf 'install: sha256 mismatch for %s\n' "$tarball" >&2
        printf 'install: expected: %s\n' "$(cat "$workdir/$tarball.sha256")" >&2
        printf 'install: actual:   %s\n' "$(sha256sum "$workdir/$tarball")" >&2
        rm -rf "$workdir"
        exit 1
    fi
    say "sha256 verified"

    # Atomic-ish swap: extract to a sibling, then move.
    extract_dir="${PKG_FRAMEWORK_HOME}.new.$$"
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    if ! tar -xzf "$workdir/$tarball" -C "$extract_dir"; then
        rm -rf "$workdir" "$extract_dir"
        die "tar extraction failed"
    fi
    # Move into place, swapping any prior install. Keep a one-deep
    # rollback for safety.
    if [ -d "$PKG_FRAMEWORK_HOME" ]; then
        rm -rf "${PKG_FRAMEWORK_HOME}.prev"
        mv "$PKG_FRAMEWORK_HOME" "${PKG_FRAMEWORK_HOME}.prev"
    fi
    mkdir -p "$(dirname "$PKG_FRAMEWORK_HOME")"
    mv "$extract_dir" "$PKG_FRAMEWORK_HOME"
    rm -rf "$workdir"
    return 0
}

# Git path: clone or update. Used when the tarball path is not
# viable (branch ref, missing tools, release not published yet).
install_via_git() {
    ref=$1
    have git || die "git not on PATH and tarball path unavailable"

    if [ -d "$PKG_FRAMEWORK_HOME/.git" ]; then
        say "updating existing checkout at $PKG_FRAMEWORK_HOME"
        git -C "$PKG_FRAMEWORK_HOME" fetch --tags --quiet origin
        git -C "$PKG_FRAMEWORK_HOME" checkout --quiet "$ref"
        if git -C "$PKG_FRAMEWORK_HOME" symbolic-ref -q HEAD >/dev/null; then
            git -C "$PKG_FRAMEWORK_HOME" pull --ff-only --quiet
        fi
    else
        say "cloning into $PKG_FRAMEWORK_HOME (ref=$ref)"
        mkdir -p "$(dirname "$PKG_FRAMEWORK_HOME")"
        git clone --quiet "$PKG_FRAMEWORK_REMOTE" "$PKG_FRAMEWORK_HOME"
        git -C "$PKG_FRAMEWORK_HOME" checkout --quiet "$ref"
    fi
}

# Pre-flight.
mkdir -p "$PKG_FRAMEWORK_BIN" || die "cannot create $PKG_FRAMEWORK_BIN"

# Resolve the ref. If the caller did not pin one, default to the
# latest published release tag.
if [ -z "$PKG_FRAMEWORK_REF" ]; then
    if PKG_FRAMEWORK_REF=$(resolve_default_ref) && [ -n "$PKG_FRAMEWORK_REF" ]; then
        say "default ref resolved to latest release: $PKG_FRAMEWORK_REF"
    else
        # Last resort: main. We say so loudly because this is the
        # supply-chain weak link and the operator deserves to know.
        PKG_FRAMEWORK_REF=main
        say "no release tags found; falling back to ref=main (NOT recommended)"
    fi
fi

# Pick a method.
case "$PKG_FRAMEWORK_METHOD" in
    tarball)
        is_release_tag "$PKG_FRAMEWORK_REF" \
            || die "method=tarball requires a release tag (got $PKG_FRAMEWORK_REF)"
        install_via_tarball "$PKG_FRAMEWORK_REF" \
            || die "tarball install failed (no fallback because method=tarball)"
        ;;
    git)
        install_via_git "$PKG_FRAMEWORK_REF"
        ;;
    auto)
        if is_release_tag "$PKG_FRAMEWORK_REF" \
           && have curl && have sha256sum && have tar; then
            if install_via_tarball "$PKG_FRAMEWORK_REF"; then
                :
            else
                say "tarball path unavailable; falling back to git clone"
                install_via_git "$PKG_FRAMEWORK_REF"
            fi
        else
            install_via_git "$PKG_FRAMEWORK_REF"
        fi
        ;;
    *) die "unknown PKG_FRAMEWORK_METHOD=$PKG_FRAMEWORK_METHOD (auto|tarball|git)" ;;
esac

cli="$PKG_FRAMEWORK_HOME/bin/pkg-framework"
[ -x "$cli" ] || die "cli not executable at $cli (install broken?)"

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
