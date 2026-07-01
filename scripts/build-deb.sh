#!/usr/bin/env bash
# Rebuild a .deb from the official .deb by repackaging its payload with our own
# pipeline. The control file and maintainer scripts are taken verbatim from
# upstream (the apt-repo registration and AppArmor userns profile are correct on
# Debian/Ubuntu, unlike on RPM where we drop them), so the result is a clean,
# functionally-equivalent rebuild rather than a byte-mirror.
#
# Usage: build-deb.sh <amd64|arm64> [out-dir]
# Requires: dpkg-deb (Debian/Ubuntu: package 'dpkg'; Fedora: 'dnf install dpkg').
# If PAYLOAD_DIR is set, it must already contain a fetch-deb.sh output (claude.deb
# + payload/ + version) and is used as-is instead of fetching/patching again -
# lets a caller building several formats share one fetch+patch across all of them.
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
# Fetch + verify + extract the official .deb, unless a caller already did this
# once and points us at the result via PAYLOAD_DIR (avoids re-fetching and
# re-patching the same payload once per output format).
FETCHED="${PAYLOAD_DIR:-$WORK}"
if [ -z "${PAYLOAD_DIR:-}" ]; then
  "$HERE/fetch-deb.sh" "$DEB_ARCH" "$FETCHED"
fi
VERSION="$(cat "$FETCHED/version")"
PKGREL="${PKGREL:-0}"
FULLVER="${VERSION}-${PKGREL}"

ROOT="$WORK/pkg"
mkdir -p "$ROOT/DEBIAN"
cp -a "$FETCHED/payload/usr" "$ROOT/usr"

# Pull control + maintainer scripts (./control ./postinst ./postrm) from upstream.
( cd "$WORK" && ar x "$FETCHED/claude.deb" control.tar.xz )
tar xf "$WORK/control.tar.xz" -C "$ROOT/DEBIAN"

# Rename the package to claude-desktop-repack (apt/dpkg shows it as ours) while
# keeping the same app identity and files: provide/conflict/replace the plain
# "claude-desktop" name so the two never coexist or shadow each other.
CTRL="$ROOT/DEBIAN/control"
sed -i 's/^Package: claude-desktop$/Package: claude-desktop-repack/' "$CTRL"
sed -i "s/^Version: .*/Version: ${FULLVER}/" "$CTRL"
grep -q '^Provides:' "$CTRL" || sed -i '/^Package: /a Provides: claude-desktop\nConflicts: claude-desktop\nReplaces: claude-desktop' "$CTRL"

mkdir -p "$OUTDIR"
OUT="$OUTDIR/claude-desktop-repack_${FULLVER}_${DEB_ARCH}.deb"
dpkg-deb --root-owner-group --build "$ROOT" "$OUT"
echo "build-deb: wrote $OUT"
