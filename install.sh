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
# v1.2.5 hardening:
#   - On-disk layout adopts the Nix/Homebrew `current` symlink
#     pattern. Each install lands at $ROOT/versions/<id>/ and an
#     atomic `ln -sfn` retargets $ROOT/current at the new version.
#     The bin symlink points at $ROOT/current/bin/pkg-framework, so
#     it never resolves to a missing path during an upgrade. The
#     prior race window between `mv HOME -> HOME.prev` and
#     `mv extract -> HOME` is closed: there is no second mv.
#   - Rollback is a one-line `ln -sfn versions/<prev> current`.
#   - Migration from the v1.2.4-and-earlier flat layout is automatic
#     and reversible: the existing $ROOT directory is renamed to
#     $ROOT.legacy.<epoch> on first upgrade, and the operator is told
#     where it went.
#
# v1.2.1 hardening (still in force):
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
#   3. Extracts into $ROOT/versions/<id>/ and atomically retargets
#      $ROOT/current at it.
#   4. Symlinks the cli into ${PKG_FRAMEWORK_BIN:-$HOME/.local/bin}.
#   5. Prints the next two commands.
#
# Idempotent: re-running with a different ref upgrades the install
# in place. Re-running with the same ref re-extracts and re-points
# `current` (a cheap no-op on the operator's terminal).
#
# POSIX sh on purpose. No bashisms; runs on Alpine, macOS, BSD.

set -eu

PKG_FRAMEWORK_OWNER="${PKG_FRAMEWORK_OWNER:-lousclues-labs}"
PKG_FRAMEWORK_REPO="${PKG_FRAMEWORK_REPO:-pkg-integration}"
PKG_FRAMEWORK_REMOTE="${PKG_FRAMEWORK_REMOTE:-https://github.com/${PKG_FRAMEWORK_OWNER}/${PKG_FRAMEWORK_REPO}.git}"
# PKG_FRAMEWORK_ROOT is the install root (the dir that holds
# versions/ and the `current` symlink). PKG_FRAMEWORK_HOME from
# v1.2.4-and-earlier was the same path under a different name; we
# accept it as a deprecated alias to keep curl|sh muscle memory
# working.
PKG_FRAMEWORK_ROOT="${PKG_FRAMEWORK_ROOT:-${PKG_FRAMEWORK_HOME:-$HOME/.local/share/pkg-framework}}"
PKG_FRAMEWORK_BIN="${PKG_FRAMEWORK_BIN:-$HOME/.local/bin}"
PKG_FRAMEWORK_METHOD="${PKG_FRAMEWORK_METHOD:-auto}"     # auto | tarball | git
PKG_FRAMEWORK_REF="${PKG_FRAMEWORK_REF:-}"
# How many old version dirs (other than `current`) to keep around for
# rollback. 1 = the previous install. Set to 0 to prune all non-current
# versions; >1 to keep more history.
PKG_FRAMEWORK_KEEP="${PKG_FRAMEWORK_KEEP:-2}"

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

# Compute a filesystem-safe version id from a ref. Tag refs map to
# themselves (e.g. v1.2.4); other refs are sanitised by replacing
# any non-alnum char with `_`.
ref_to_id() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9.+-' '_'
}

# If $ROOT exists in the pre-v1.2.5 flat layout (bin/pkg-framework
# directly inside it, no `current` symlink), move it aside so we can
# lay down the versions/ tree without colliding. The old install is
# preserved at $ROOT.legacy.<epoch> for one-step rollback.
migrate_legacy_layout() {
    [ -e "$PKG_FRAMEWORK_ROOT" ] || return 0
    [ -L "$PKG_FRAMEWORK_ROOT/current" ] && return 0
    # New layout already? (current is the only marker we trust.)
    if [ -d "$PKG_FRAMEWORK_ROOT/versions" ] && [ ! -e "$PKG_FRAMEWORK_ROOT/bin/pkg-framework" ]; then
        return 0
    fi
    # Old flat layout. Rename aside.
    epoch=$(date +%s 2>/dev/null || echo 'unknown')
    legacy="${PKG_FRAMEWORK_ROOT}.legacy.${epoch}"
    say "migrating pre-v1.2.5 flat layout: ${PKG_FRAMEWORK_ROOT} -> ${legacy}"
    mv "$PKG_FRAMEWORK_ROOT" "$legacy" \
        || die "could not rename ${PKG_FRAMEWORK_ROOT} for migration"
    say "  legacy install preserved; remove with 'rm -rf ${legacy}' when you have verified the new install"
}

# Atomically retarget $ROOT/current at versions/<id>. Uses the
# temp-symlink + mv pattern because rename(2) is the only POSIX
# primitive that replaces an existing symlink atomically; bare
# `ln -sfn` on some implementations does unlink+symlink with a
# window.
retarget_current() {
    id=$1
    tmp="${PKG_FRAMEWORK_ROOT}/.current.tmp.$$"
    rm -f "$tmp"
    ln -s "versions/$id" "$tmp"
    mv -f "$tmp" "${PKG_FRAMEWORK_ROOT}/current" \
        || die "could not retarget ${PKG_FRAMEWORK_ROOT}/current"
}

# Keep `current`, the version it points at, and the
# PKG_FRAMEWORK_KEEP most-recent other versions. Drop anything older.
# Touch-only-what-you-need; failures here are warnings, not fatal.
prune_old_versions() {
    keep="$PKG_FRAMEWORK_KEEP"
    [ -d "$PKG_FRAMEWORK_ROOT/versions" ] || return 0
    cur_target=$(readlink "${PKG_FRAMEWORK_ROOT}/current" 2>/dev/null || echo '')
    cur_id="${cur_target#versions/}"
    # ls -t orders newest mtime first. We keep `current` always, plus
    # the next $keep entries; everything beyond that is dropped.
    n=0
    for v in $(cd "$PKG_FRAMEWORK_ROOT/versions" && ls -1t 2>/dev/null); do
        if [ "$v" = "$cur_id" ]; then continue; fi
        n=$((n + 1))
        if [ "$n" -le "$keep" ]; then continue; fi
        rm -rf "${PKG_FRAMEWORK_ROOT}/versions/$v" 2>/dev/null \
            && say "pruned old version: $v"
    done
}

# Tarball path: download + verify sha256 + extract into a fresh
# versions/<id>/ dir + retarget `current`. Only used when the ref
# is a release tag and the tools are present. Returns 0 on success;
# non-zero if the tarball is unavailable (caller falls back to git).
# Verification failures exit hard, NOT return non-zero, because a
# bad sha256 must not silently fall through to the looser git path.
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

    id=$(ref_to_id "$ref")
    mkdir -p "${PKG_FRAMEWORK_ROOT}/versions"
    staging="${PKG_FRAMEWORK_ROOT}/versions/.staging.${id}.$$"
    rm -rf "$staging"
    mkdir -p "$staging"
    if ! tar -xzf "$workdir/$tarball" -C "$staging"; then
        rm -rf "$workdir" "$staging"
        die "tar extraction failed"
    fi
    target="${PKG_FRAMEWORK_ROOT}/versions/$id"
    # If a previous install of this id is already in place, rotate it
    # aside as `<id>.replaced.<pid>` so the rename can proceed; the
    # prune step picks it up. We never overwrite a populated dir in
    # one mv (rename(2) is non-atomic on non-empty target dirs and
    # would fail with ENOTEMPTY).
    if [ -e "$target" ]; then
        mv "$target" "${target}.replaced.$$" \
            || die "could not rotate existing ${target}"
    fi
    mv "$staging" "$target" \
        || die "could not place new version at ${target}"
    rm -rf "$workdir" "${target}.replaced.$$" 2>/dev/null || true
    retarget_current "$id"
    return 0
}

# Git path: clone into a fresh versions/<id>/ dir + retarget
# `current`. Used when the tarball path is not viable (branch ref,
# missing tools, release not published yet).
install_via_git() {
    ref=$1
    have git || die "git not on PATH and tarball path unavailable"

    id=$(ref_to_id "$ref")
    mkdir -p "${PKG_FRAMEWORK_ROOT}/versions"
    staging="${PKG_FRAMEWORK_ROOT}/versions/.staging.${id}.$$"
    rm -rf "$staging"
    say "cloning into versions/$id (ref=$ref)"
    git clone --quiet "$PKG_FRAMEWORK_REMOTE" "$staging" \
        || { rm -rf "$staging"; die "git clone failed"; }
    git -C "$staging" checkout --quiet "$ref" \
        || { rm -rf "$staging"; die "git checkout $ref failed"; }
    target="${PKG_FRAMEWORK_ROOT}/versions/$id"
    if [ -e "$target" ]; then
        mv "$target" "${target}.replaced.$$" \
            || die "could not rotate existing ${target}"
    fi
    mv "$staging" "$target" \
        || die "could not place new version at ${target}"
    rm -rf "${target}.replaced.$$" 2>/dev/null || true
    retarget_current "$id"
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

# Lay down (or detect) the v1.2.5 layout.
migrate_legacy_layout
mkdir -p "${PKG_FRAMEWORK_ROOT}/versions"

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

# Verify and link.
cli="${PKG_FRAMEWORK_ROOT}/current/bin/pkg-framework"
[ -x "$cli" ] || die "cli not executable at $cli (install broken?)"

link="$PKG_FRAMEWORK_BIN/pkg-framework"
ln -sfn "$cli" "$link"
say "symlinked $link -> $cli"

installed_version=$(tr -d '\r\n' < "${PKG_FRAMEWORK_ROOT}/current/VERSION" 2>/dev/null || echo "?")
say "pkg-framework $installed_version installed (ref: $PKG_FRAMEWORK_REF)"

prune_old_versions

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

upgrade later: re-run this installer.

rollback (one-line): ln -sfn versions/<prev-id> ${PKG_FRAMEWORK_ROOT}/current
  prior version dirs live at ${PKG_FRAMEWORK_ROOT}/versions/
EOF
