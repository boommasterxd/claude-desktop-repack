#!/usr/bin/env bash
# Assemble the GitHub Pages site: the install repos' metadata (currently the dnf
# repo) plus the signing pubkey and a landing page. Packages stay on the release;
# only metadata + instructions live here. Extended per format (arch, apt) over time.
#
# Usage: build-pages-site.sh <dist-dir> <version> <pkgrel> <owner/repo> <site-dir>
set -euo pipefail

DIST="${1:?usage: build-pages-site.sh <dist> <version> <pkgrel> <owner/repo> <site>}"
V="${2:?version}"; REL="${3:?pkgrel}"; REPO="${4:?owner/repo}"; SITE="${5:?site dir}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"
PAGES_URL="https://${OWNER}.github.io/${NAME}"
KEY_FP="${GPG_KEY_ID:-}"
PACMAN_SIGLEVEL="$([ -n "$KEY_FP" ] && echo Required || echo Optional)"

rm -rf "$SITE"; mkdir -p "$SITE"

# dnf/zypper repo (metadata only; packages point at the release).
bash "$HERE/build-rpm-repo.sh" "$DIST" "$V" "$REL" "$REPO" "$SITE"
# pacman repo (per-arch db + packages on Pages, signed).
bash "$HERE/build-arch-repo.sh" "$DIST" "$SITE"
# apt repo (pool + signed Release on Pages).
bash "$HERE/build-apt-repo.sh" "$DIST" "$SITE"

# shields.io endpoint badges (release + per-repo + AppImage/tarball versions),
# read from the metadata just built above and the artifacts in DIST, so each
# reflects the version actually served by that channel.
bash "$HERE/build-badges.sh" "$SITE" "$V" "$REL" "$DIST"

# Signing pubkey (referenced by the .repo's gpgkey=).
cp "$HERE/../RELEASE-PUBKEY.asc" "$SITE/RELEASE-PUBKEY.asc"

# Landing page with install instructions.
cat > "$SITE/index.html" <<EOF
<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Claude Desktop (repack) - install</title>
<style>
 body{font:16px/1.6 system-ui,sans-serif;max-width:760px;margin:2rem auto;padding:0 1rem;color:#111}
 h1{margin-bottom:.2rem} .sub{color:#666;margin-top:0}
 h2{margin-top:2rem} code,pre{background:#f4f4f5;border-radius:6px}
 pre{padding:.8rem 1rem;overflow:auto} code{padding:.1rem .3rem}
 a{color:#7c3aed}
</style></head><body>
<h1>Claude Desktop <span style="color:#7c3aed">(repack)</span></h1>
<p class="sub">Unofficial Linux repackage of Anthropic's official build. Version ${V}-${REL}.</p>

<h2>Fedora / RHEL / openSUSE (dnf/zypper)</h2>
<pre>sudo dnf config-manager --add-repo ${PAGES_URL}/rpm/claude-desktop-repack.repo
sudo dnf install claude-desktop-repack</pre>
<p>Updates come with <code>sudo dnf upgrade</code>. Packages are served from the GitHub
Release; only the repo metadata is hosted here.</p>

<h2>Arch / Manjaro (pacman)</h2>
<pre>curl -fsSL ${PAGES_URL}/RELEASE-PUBKEY.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key ${KEY_FP}

# add to /etc/pacman.conf:
[claude-desktop-repack]
SigLevel = ${PACMAN_SIGLEVEL}
Server = ${PAGES_URL}/arch/\$arch

sudo pacman -Sy claude-desktop-repack</pre>

<h2>Debian / Ubuntu (apt)</h2>
<pre>curl -fsSL ${PAGES_URL}/RELEASE-PUBKEY.asc | gpg --dearmor | sudo tee /usr/share/keyrings/claude-desktop-repack.gpg &gt;/dev/null
echo "deb [signed-by=/usr/share/keyrings/claude-desktop-repack.gpg] ${PAGES_URL}/deb stable main" | sudo tee /etc/apt/sources.list.d/claude-desktop-repack.list
sudo apt update &amp;&amp; sudo apt install claude-desktop-repack</pre>
<p>Anthropic's <a href="https://code.claude.com/docs/en/desktop-linux">official apt repo</a>
is also a good option for Debian/Ubuntu.</p>

<h2>AppImage (any distro, auto-updating)</h2>
<p>Download the <code>.AppImage</code> from the
<a href="https://github.com/${REPO}/releases/latest">latest release</a>, or add it to
<a href="https://github.com/mijorus/gearlever">GearLever</a>: it reads the embedded
update URL and pulls only the changed blocks (zsync delta), never the whole file again.</p>

<h2>Nix / NixOS (flake)</h2>
<pre>NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure github:${REPO}</pre>

<p style="margin-top:2rem;color:#666;font-size:.9rem">
Verify downloads with the <a href="${PAGES_URL}/RELEASE-PUBKEY.asc">signing key</a> +
each release's <code>SHA256SUMS.txt.asc</code>. Not affiliated with Anthropic.</p>
</body></html>
EOF

# Pages serves a 404 for unknown paths; a .nojekyll keeps dot-dirs (repodata) intact.
touch "$SITE/.nojekyll"

echo "build-pages-site: assembled $SITE (rpm repo + pubkey + landing)"
