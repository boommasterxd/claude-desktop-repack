#!/usr/bin/env bash
# Build a signed pacman repository under <site>/arch/<arch>/ for GitHub Pages.
# pacman repos are per-architecture, so we make one db per arch; users point
# pacman at Server = <pages>/arch/$arch. The packages live next to the db (pacman
# fetches Server/<filename>), so they are copied onto Pages too (latest only, so a
# couple of files). db + packages are GPG-signed (SigLevel = Required); users add
# the key to pacman's keyring.
#
# Usage: build-arch-repo.sh <dist-dir-with-pkg.tar.zst> <site-dir>
# Requires: docker (repo-add via archlinux), gpg with GPG_KEY_ID for signing
# (unsigned if GPG_KEY_ID is empty; then document SigLevel = Optional).
set -euo pipefail

DIST="${1:?usage: build-arch-repo.sh <dist> <site>}"
SITE="${2:?site dir}"
DBNAME="claude-desktop-repack"

sign() { if [ -n "${GPG_KEY_ID:-}" ]; then gpg --batch --yes --local-user "$GPG_KEY_ID" --output "$1.sig" --detach-sign "$1"; fi; }

for pkg in "$DIST"/${DBNAME}-*.pkg.tar.zst; do
  base="$(basename "$pkg")"
  case "$base" in *-x86_64.pkg.tar.zst) CARCH=x86_64 ;; *-aarch64.pkg.tar.zst) CARCH=aarch64 ;; *) continue ;; esac
  OUT="$SITE/arch/$CARCH"
  mkdir -p "$OUT"
  cp "$pkg" "$OUT/"
  ( cd "$OUT" && sign "$base" )

  # Build the per-arch db with repo-add (archlinux container). chown back so the
  # host can read/clean the root-created files.
  docker run --rm -e HU="$(id -u)" -e HG="$(id -g)" -v "$OUT":/w -w /w archlinux:latest bash -c "
    repo-add ${DBNAME}.db.tar.gz ${base} >/dev/null 2>&1
    # repo-add makes db.tar.gz + a symlink db -> db.tar.gz; ship the real file as .db.
    rm -f ${DBNAME}.db ${DBNAME}.files ${DBNAME}.files.tar.gz
    mv ${DBNAME}.db.tar.gz ${DBNAME}.db
    chown -R \$HU:\$HG /w
  "
  ( cd "$OUT" && sign "${DBNAME}.db" )
  echo "build-arch-repo: $CARCH -> $OUT ($(ls "$OUT" | tr '\n' ' '))"
done
