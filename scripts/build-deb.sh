#!/usr/bin/env bash
# Rebuild a .deb from the official .deb by repackaging its payload with our own
# pipeline. The control file and maintainer scripts are taken verbatim from
# upstream (the apt-repo registration and AppArmor userns profile are correct on
# Debian/Ubuntu, unlike on RPM where we drop them), so the result is a clean,
# functionally-equivalent rebuild rather than a byte-mirror.
#
# Usage: build-deb.sh <amd64|arm64> [out-dir]
# Requires: dpkg-deb (Debian/Ubuntu: package 'dpkg'; Fedora: 'dnf install dpkg').
set -euo pipefail

DEB_ARCH="${1:?usage: build-deb.sh <amd64|arm64> [out-dir]}"
OUTDIR="${2:-dist}"
HERE="$(cd "$(dirname "$0")" && pwd)"

case "$DEB_ARCH" in
  amd64|arm64) ;;
  *) echo "build-deb: unknown arch '$DEB_ARCH' (use amd64|arm64)" >&2; exit 1 ;;
esac
command -v dpkg-deb >/dev/null 2>&1 || {
  echo "build-deb: dpkg-deb not found (Debian/Ubuntu: package 'dpkg'; Fedora: 'dnf install dpkg')" >&2
  exit 1
}

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
"$HERE/fetch-deb.sh" "$DEB_ARCH" "$WORK"
VERSION="$(cat "$WORK/version")"

ROOT="$WORK/pkg"
mkdir -p "$ROOT/DEBIAN"
cp -a "$WORK/payload/usr" "$ROOT/usr"

# Pull control + maintainer scripts (./control ./postinst ./postrm) from upstream.
( cd "$WORK" && ar x claude.deb control.tar.xz )
tar xf "$WORK/control.tar.xz" -C "$ROOT/DEBIAN"

mkdir -p "$OUTDIR"
OUT="$OUTDIR/claude-desktop_${VERSION}_${DEB_ARCH}.deb"
dpkg-deb --root-owner-group --build "$ROOT" "$OUT"
echo "build-deb: wrote $OUT"
