#!/usr/bin/env bash
# Emit shields.io "endpoint" badge JSONs under <site>/badges/, one per install
# repo, the release-only formats (AppImage, tarball), plus the GitHub release.
# Each reads the version actually recorded in that channel's freshly built
# metadata/artifact (not just the passed version), so a badge proves the channel
# really carries that version; on any parse miss it falls back to <V>-<REL>.
#
# Why endpoint JSON instead of a dynamic shields query: we serve stable, always
# valid JSON from our own Pages site, so shields never errors and GitHub's Camo
# image proxy only ever caches a valid badge (no more "invalid" flicker), and
# there is no GitHub API rate limit in the path.
#
# Usage: build-badges.sh <site-dir> <version> <pkgrel> [dist-dir]
#   dist-dir (optional): the built artifacts, used to derive the AppImage/tarball
#   versions from their real filenames; omit to fall back to <V>-<REL> for those.
set -euo pipefail

SITE="${1:?usage: build-badges.sh <site> <version> <pkgrel> [dist]}"
V="${2:?version}"; REL="${3:?pkgrel}"; DIST="${4:-}"
FALLBACK="${V}-${REL}"
COLOR="7c3aed"
BADGES="$SITE/badges"
mkdir -p "$BADGES"

# {schemaVersion,label,message,color} is the shields endpoint contract.
emit() { printf '{"schemaVersion":1,"label":"%s","message":"%s","color":"%s"}\n' "$1" "$2" "$COLOR" > "$BADGES/$3"; }

# apt: "Version: <ver>-<rel>" in the generated Packages index.
deb_ver="$(awk '/^Version:/{print $2; exit}' "$SITE/deb/dists/stable/main/binary-amd64/Packages" 2>/dev/null || true)"
# rpm: <version ... ver="X" rel="Y"/> in primary.xml.gz.
rpm_ver="$(zcat "$SITE"/rpm/repodata/*primary.xml.gz 2>/dev/null \
  | grep -om1 'ver="[^"]*" rel="[^"]*"' \
  | sed -E 's/ver="([^"]*)" rel="([^"]*)"/\1-\2/' || true)"
# pacman: version encoded in the .pkg.tar.zst filename (…-<ver>-<rel>-<arch>.pkg.tar.zst).
arch_pkg="$(ls "$SITE"/arch/x86_64/claude-desktop-repack-*.pkg.tar.zst 2>/dev/null | head -1 || true)"
arch_ver="$([ -n "$arch_pkg" ] && basename "$arch_pkg" | sed -E 's/^claude-desktop-repack-(.*)-x86_64\.pkg\.tar\.zst$/\1/' || true)"

# Release-only formats (no repo): version parsed from the built artifact filename
# in DIST, if given. AppImage: …-<ver>-<rel>-x86_64.AppImage. tarball: …-<ver>-<rel>-linux.tar.gz.
appimg_ver=""; tar_ver=""
if [ -n "$DIST" ]; then
  ai="$(ls "$DIST"/claude-desktop-repack-*-x86_64.AppImage 2>/dev/null | head -1 || true)"
  appimg_ver="$([ -n "$ai" ] && basename "$ai" | sed -E 's/^claude-desktop-repack-(.*)-x86_64\.AppImage$/\1/' || true)"
  tb="$(ls "$DIST"/claude-desktop-repack-*-linux.tar.gz 2>/dev/null | head -1 || true)"
  tar_ver="$([ -n "$tb" ] && basename "$tb" | sed -E 's/^claude-desktop-repack-(.*)-linux\.tar\.gz$/\1/' || true)"
fi

emit "release"  "$FALLBACK"                    release.json
emit "dnf"      "${rpm_ver:-$FALLBACK}"        fedora.json
emit "pacman"   "${arch_ver:-$FALLBACK}"       arch.json
emit "apt"      "${deb_ver:-$FALLBACK}"        debian.json
emit "appimage" "${appimg_ver:-$FALLBACK}"     appimage.json
emit "tarball"  "${tar_ver:-$FALLBACK}"        tarball.json

echo "build-badges: wrote $BADGES (release=$FALLBACK dnf=${rpm_ver:-$FALLBACK} pacman=${arch_ver:-$FALLBACK} apt=${deb_ver:-$FALLBACK} appimage=${appimg_ver:-$FALLBACK} tarball=${tar_ver:-$FALLBACK})"
