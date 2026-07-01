#!/usr/bin/env bash
# Build a relocatable generic tarball from the official .deb for the given arch.
# Output: claude-desktop-repack-<v>-linux[-aarch64].tar.gz
#
# Usage: build-tarball.sh <amd64|arm64> [out-dir]
# If PAYLOAD_DIR is set, it must already contain a fetch-deb.sh output (claude.deb
# + payload/ + version) and is used as-is instead of fetching/patching again -
# lets a caller building several formats share one fetch+patch across all of them.
set -euo pipefail

DEB_ARCH="${1:?usage: build-tarball.sh <amd64|arm64> [out-dir]}"
OUTDIR="${2:-dist}"
HERE="$(cd "$(dirname "$0")" && pwd)"

case "$DEB_ARCH" in
  amd64) SUFFIX="" ;;
  arm64) SUFFIX="-aarch64" ;;
  *) echo "build-tarball: unknown arch '$DEB_ARCH'" >&2; exit 1 ;;
esac

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

NAME="claude-desktop-repack-${VERSION}-${PKGREL}-linux${SUFFIX}"
DIR="$WORK/$NAME"
mkdir -p "$DIR"
cp -a "$FETCHED/payload/usr" "$DIR/usr"
rm -rf "$DIR/usr/share/lintian"   # Debian packaging-lint metadata, meaningless off Debian

# Relocatable launcher. chrome-sandbox needs root+setuid which a user-extracted
# tree cannot provide, so default to --no-sandbox (same trade-off every portable
# Electron app makes). Users who want the namespace sandbox can chown root +
# chmod 4755 usr/lib/claude-desktop/chrome-sandbox and drop the flag.
cat > "$DIR/claude-desktop" <<'EOF'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "$HERE/usr/lib/claude-desktop/claude-desktop" --no-sandbox "$@"
EOF
chmod +x "$DIR/claude-desktop"

mkdir -p "$OUTDIR"
tar czf "$OUTDIR/${NAME}.tar.gz" -C "$WORK" "$NAME"
echo "build-tarball: wrote $OUTDIR/${NAME}.tar.gz"
