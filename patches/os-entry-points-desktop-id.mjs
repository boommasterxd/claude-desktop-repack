// Make the "OS entry points" feature (adds Desktop Actions - New Chat, New
// Claude Code Session, Continue Last Session, Sessions Waiting for You - to the
// app's Linux launcher entry, so file managers/app launchers that support
// XDG Desktop Actions show them as a jump list) find the desktop file this
// repack actually installs.
//
// The app reads the packaged, system-installed `.desktop` file from
// `/usr/share/applications/<id>.desktop` (hard-coding upstream's own current
// filename, `com.anthropic.Claude.desktop`) to build an augmented copy with the
// extra actions, written to `$XDG_DATA_HOME/applications/<id>.desktop` (see
// `scripts/fetch-deb.sh`'s "canonicalize" step and CLAUDE.md). Every packaged
// format here (rpm/deb/tarball/AppImage/Arch/Nix) installs the file as
// `claude-desktop.desktop` instead, for a filename stable across upstream's own
// desktop-entry renames (it did this once already, at 1.19367.0). So the
// hard-coded read path never matches on this repack, and the feature silently
// no-ops (`osEntryPoints: packaged desktop entry not found`).
//
// This patch repoints that one literal at our canonical filename, matching
// scripts/fetch-deb.sh's rename target exactly.

export const name = "os-entry-points-desktop-id";
export const description =
  "points the OS entry points (Desktop Actions jump list) feature at this repack's `claude-desktop.desktop`, not upstream's `com.anthropic.Claude.desktop`";

const CANONICAL_ID = "claude-desktop.desktop";

// Anchor: the variable assigned the literal `com.anthropic.Claude.desktop`,
// immediately followed by another variable assigned a template embedding
// `/usr/share/applications/${<same var>}` - ties the match to both the exact
// desktop-entry id upstream currently hard-codes AND the system applications
// directory it is read from, not just to the id string alone.
const ANCHOR_RE =
  /([\w$]+)=(["'`])com\.anthropic\.Claude\.desktop\2,([\w$]+)=(["'`])\/usr\/share\/applications\/\$\{\1\}\4/g;

export function apply(code) {
  const matches = [...code.matchAll(ANCHOR_RE)];
  if (matches.length !== 1) {
    throw new Error(`${name}: anchor matched ${matches.length} time(s) (expected 1) - upstream shape changed, re-anchor`);
  }

  const out = code.replace(ANCHOR_RE, (_m, idVar, q1, pathVar, q2) => `${idVar}=${q1}${CANONICAL_ID}${q1},${pathVar}=${q2}/usr/share/applications/\${${idVar}}${q2}`);

  if (!out.includes(`${CANONICAL_ID}\``) && !out.includes(`${CANONICAL_ID}"`) && !out.includes(`${CANONICAL_ID}'`)) {
    throw new Error(`${name}: end-state marker missing after patch`);
  }
  return out;
}
