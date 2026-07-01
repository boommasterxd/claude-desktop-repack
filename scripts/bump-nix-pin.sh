#!/usr/bin/env bash
# Open a PR that bumps packaging/nix/package.nix to a new upstream version + the
# per-arch .deb sha256. The Nix flake pins these in-repo (unlike the Arch PKGBUILD,
# which is rendered fresh per release), so `nix profile install github:...` would
# otherwise lag upstream until edited by hand. Run this after a release for a NEW
# upstream version; it is a no-op if package.nix is already at that version.
#
# Respects branch protection: it pushes a branch and opens a PR (never pushes to
# main). Needs GH_TOKEN with contents:write + pull-requests:write.
#
# Usage: bump-nix-pin.sh <version>
# Testing: set BUMP_DRY_RUN=1 to edit package.nix and print the diff without git/gh.
#          set BUMP_SHA_AMD64 / BUMP_SHA_ARM64 to skip the apt-index lookup.
set -euo pipefail

V="${1:?usage: bump-nix-pin.sh <version>}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$HERE/../packaging/nix/package.nix"

if grep -q "version = \"$V\";" "$PKG"; then
  echo "bump-nix-pin: package.nix already pinned to $V - nothing to do"
  exit 0
fi

# Per-arch .deb sha256 (from the apt index, unless provided for testing).
SHA_AMD64="${BUMP_SHA_AMD64:-}"
SHA_ARM64="${BUMP_SHA_ARM64:-}"
if [ -z "$SHA_AMD64" ]; then eval "$(bash "$HERE/detect-version.sh" amd64)"; SHA_AMD64="$SHA256"; fi
if [ -z "$SHA_ARM64" ]; then eval "$(bash "$HERE/detect-version.sh" arm64)"; SHA_ARM64="$SHA256"; fi

for s in "$SHA_AMD64" "$SHA_ARM64"; do
  printf '%s' "$s" | grep -qE '^[0-9a-f]{64}$' || { echo "bump-nix-pin: bad sha256 '$s'" >&2; exit 1; }
done

# Update the version and both per-arch sha256s (each inside its own block).
python3 - "$PKG" "$V" "$SHA_AMD64" "$SHA_ARM64" <<'PY'
import re, sys
path, version, amd, arm = sys.argv[1:5]
s = open(path).read()
s = re.sub(r'version = "[0-9.]+";', f'version = "{version}";', s, count=1)
s = re.sub(r'(x86_64-linux = \{[^}]*?sha256 = ")[0-9a-f]{64}(")',  r'\g<1>' + amd + r'\g<2>', s, flags=re.S)
s = re.sub(r'(aarch64-linux = \{[^}]*?sha256 = ")[0-9a-f]{64}(")', r'\g<1>' + arm + r'\g<2>', s, flags=re.S)
open(path, 'w').write(s)
PY

if [ "${BUMP_DRY_RUN:-}" = "1" ]; then
  echo "=== dry run: package.nix diff ==="
  git -C "$HERE/.." --no-pager diff -- packaging/nix/package.nix || true
  exit 0
fi

BR="nix-bump-$V"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git checkout -B "$BR"
git add "$PKG"
git commit -q -m "chore(nix): bump flake pin to Claude Desktop $V"
git push -f origin "$BR"

gh pr create --base main --head "$BR" \
  --title "chore(nix): bump flake pin to $V" \
  --body "Automated bump: new upstream **Claude Desktop $V**. Updates the pinned \`version\` + per-arch \`.deb\` sha256 in \`packaging/nix/package.nix\` so \`nix profile install github:${GITHUB_REPOSITORY:-<repo>}\` tracks the current release. Merge to publish." \
  2>/dev/null || gh pr edit "$BR" --title "chore(nix): bump flake pin to $V" || true
echo "bump-nix-pin: opened/updated PR for $V"
