#!/usr/bin/env bash
# Render packaging/arch/PKGBUILD.in into a ready-to-use PKGBUILD that sources the
# published release tarballs (for `makepkg` / AUR-style users). Prints to stdout.
#
# Usage: render-pkgbuild.sh <version> <pkgrel> <owner/repo> <dist-dir-with-tarballs>
set -euo pipefail

V="${1:?version}"; REL="${2:?pkgrel}"; REPO="${3:?owner/repo}"; DIST="${4:?dist dir}"
HERE="$(cd "$(dirname "$0")" && pwd)"

base="https://github.com/${REPO}/releases/download/v${V}-${REL}"
x64="claude-desktop-repack-${V}-${REL}-linux.tar.gz"
a64="claude-desktop-repack-${V}-${REL}-linux-aarch64.tar.gz"
sx="$(sha256sum "$DIST/$x64" | cut -d' ' -f1)"
sa="$(sha256sum "$DIST/$a64" | cut -d' ' -f1)"

sed -e "s/{{VERSION}}/$V/g" \
    -e "s/{{PKGREL}}/$REL/g" \
    -e "s#{{REPO}}#$REPO#g" \
    -e "s#{{SRC_X64}}#${x64}::${base}/${x64}#g" \
    -e "s#{{SRC_AARCH64}}#${a64}::${base}/${a64}#g" \
    -e "s/{{SHA_X64}}/$sx/g" \
    -e "s/{{SHA_AARCH64}}/$sa/g" \
    "$HERE/../packaging/arch/PKGBUILD.in"
