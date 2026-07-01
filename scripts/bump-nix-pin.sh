#!/usr/bin/env bash
# Open a PR bumping packaging/nix/package.nix to the just-released tarballs.
#
# The Nix flake is release-coupled: it fetches THIS repo's release tarball, so its
# pins (version, pkgrel, per-arch tarball sha256) must track every release. Run
# this after the release is published, pointing at the dist/ dir that holds the
# tarballs. main is protected, so it opens a PR (never pushes to main). No-op if
# package.nix is already at that version+pkgrel.
#
# Usage: bump-nix-pin.sh <version> <pkgrel> <dist-dir-with-tarballs>
# Testing: BUMP_DRY_RUN=1 edits package.nix + prints the diff, skips git/gh.
set -euo pipefail

V="${1:?usage: bump-nix-pin.sh <version> <pkgrel> <dist-dir>}"
REL="${2:?pkgrel}"
DIST="${3:?dist dir}"
HERE="$(cd "$(dirname "$0")" && pwd)"
PKG="$HERE/../packaging/nix/package.nix"

x64="$DIST/claude-desktop-repack-${V}-${REL}-linux.tar.gz"
a64="$DIST/claude-desktop-repack-${V}-${REL}-linux-aarch64.tar.gz"
[ -f "$x64" ] && [ -f "$a64" ] || { echo "bump-nix-pin: tarballs not found in $DIST" >&2; exit 1; }
SHA_X64="$(sha256sum "$x64" | cut -d' ' -f1)"
SHA_A64="$(sha256sum "$a64" | cut -d' ' -f1)"

if grep -q "version = \"$V\";" "$PKG" && grep -q "pkgrel = \"$REL\";" "$PKG" && grep -q "$SHA_X64" "$PKG"; then
  echo "bump-nix-pin: package.nix already pinned to $V-$REL - nothing to do"
  exit 0
fi

python3 - "$PKG" "$V" "$REL" "$SHA_X64" "$SHA_A64" <<'PY'
import re, sys
path, ver, rel, sx, sa = sys.argv[1:6]
s = open(path).read()
s = re.sub(r'version = "[0-9.]+";', f'version = "{ver}";', s, count=1)
s = re.sub(r'pkgrel = "[0-9]+";', f'pkgrel = "{rel}";', s, count=1)
s = re.sub(r'(x86_64-linux = \{[^}]*?sha256 = ")[0-9a-f]{64}(")',  r'\g<1>' + sx + r'\g<2>', s, flags=re.S)
s = re.sub(r'(aarch64-linux = \{[^}]*?sha256 = ")[0-9a-f]{64}(")', r'\g<1>' + sa + r'\g<2>', s, flags=re.S)
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
git commit -q -m "chore(nix): bump flake pin to $V-$REL"
git push -f origin "$BR"

gh pr create --base main --head "$BR" \
  --title "chore(nix): bump flake pin to $V-$REL" \
  --body "Automated: release **v$V-$REL**. Updates the release-tarball pin (version + pkgrel + per-arch sha256) in \`packaging/nix/package.nix\` so \`nix profile install github:${GITHUB_REPOSITORY:-<repo>}\` tracks the current release. Auto-merges once \`gitleaks\` passes." \
  2>/dev/null || gh pr edit "$BR" --title "chore(nix): bump flake pin to $V-$REL" || true

# Arm auto-merge (allow_auto_merge is on; only the gitleaks check gates main).
# NOTE: for auto-merge to actually complete, this must run with a PAT
# (NIX_BUMP_TOKEN) - a PR opened by GITHUB_TOKEN does not trigger gitleaks, so the
# required check would never post and auto-merge would sit pending. With a PAT,
# gitleaks runs, passes, and GitHub squash-merges automatically.
gh pr merge "$BR" --auto --squash 2>/dev/null || echo "bump-nix-pin: auto-merge not armed (needs allow_auto_merge + a PR-triggering token)"
echo "bump-nix-pin: opened/updated PR for $V-$REL"
