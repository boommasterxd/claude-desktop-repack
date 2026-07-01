#!/usr/bin/env bash
# Download the official Claude Desktop .deb for an arch, verify its SHA256
# against the apt index, and extract the payload into a build root.
#
# Usage: fetch-deb.sh <amd64|arm64> <out-dir>
# Produces:
#   <out-dir>/claude.deb            the raw package
#   <out-dir>/payload/              extracted file tree (usr/...)
#   <out-dir>/version               the detected version string
set -euo pipefail

ARCH="${1:?usage: fetch-deb.sh <amd64|arm64> <out-dir>}"
OUT="${2:?usage: fetch-deb.sh <amd64|arm64> <out-dir>}"
HERE="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$OUT"
eval "$("$HERE/detect-version.sh" "$ARCH")"   # sets VERSION / DEB_URL / SHA256 / SIZE

echo "fetch-deb: version=$VERSION arch=$ARCH"
echo "fetch-deb: downloading $DEB_URL"
curl -fsSL -o "$OUT/claude.deb" "$DEB_URL"

got="$(sha256sum "$OUT/claude.deb" | cut -d' ' -f1)"
if [ "$got" != "$SHA256" ]; then
  echo "fetch-deb: SHA256 mismatch! expected=$SHA256 got=$got" >&2
  exit 1
fi
echo "fetch-deb: SHA256 OK"

# Extract: .deb is an ar archive containing data.tar.xz (the file tree).
rm -rf "$OUT/payload"; mkdir -p "$OUT/payload"
( cd "$OUT" && ar x claude.deb data.tar.xz )
tar xpf "$OUT/data.tar.xz" -C "$OUT/payload"

# Strictness guard: assert the expected upstream layout. If this fails the
# upstream package was restructured and the packaging recipes must be revisited.
test -x "$OUT/payload/usr/lib/claude-desktop/claude-desktop" \
  || { echo "fetch-deb: expected /usr/lib/claude-desktop/claude-desktop missing - upstream layout changed" >&2; exit 1; }
test -u "$OUT/payload/usr/lib/claude-desktop/chrome-sandbox" \
  || echo "fetch-deb: WARNING chrome-sandbox is not setuid in the payload" >&2

printf '%s\n' "$VERSION" > "$OUT/version"

# Guard: fail the build if upstream introduced new, unreviewed absolute system
# paths that might be Debian-specific and break non-Debian distros (like the OVMF
# firmware paths cowork-firmware-paths fixes). Runs on the pristine asar and
# prints NATIVE-PATH-DRIFT so CI can open a per-version issue listing them.
node "$HERE/check-native-paths.mjs" "$OUT/payload" "$VERSION"

# Apply the minimal Linux patches to the payload's app.asar (auto-discovered from
# patches/). Needs node + node_modules (npm ci). Fails loud (naming the patches)
# if a pattern no longer matches, so CI can open a per-version issue.
node "$HERE/patch-payload.mjs" "$OUT/payload" "$VERSION"

# Add the hotkey helper next to the upstream launcher (which stays a plain
# symlink, untouched): a bug here can never block the app from starting.
install -Dm755 "$HERE/../packaging/launcher/claude-desktop-hotkey" \
  "$OUT/payload/usr/bin/claude-desktop-hotkey"

echo "fetch-deb: payload ready in $OUT/payload (version $VERSION, patched)"
