#!/usr/bin/env node
// Guard against NEW absolute system paths appearing in the upstream bundle that
// we have not reviewed for cross-distro correctness.
//
// Why: the official .deb hard-codes Debian paths (e.g. the OVMF firmware under
// /usr/share/OVMF/... that `cowork-firmware-paths` fixes). When a new upstream
// version introduces another absolute /usr/share, /usr/lib, /usr/libexec (etc.)
// literal, it may be Debian-specific and silently break Fedora/RHEL/Arch. This
// check compares every such literal against a reviewed allowlist and FAILS the
// build on anything new, so the maintainer classifies it instead of shipping a
// possibly-broken package.
//
// Usage:
//   node scripts/check-native-paths.mjs <payloadDir> [version]   # check (exit 1 on drift)
//   node scripts/check-native-paths.mjs <payloadDir> --update     # (re)generate baseline
//
// On drift it prints a machine-readable line CI can turn into an issue:
//   NATIVE-PATH-DRIFT version=<v> paths=<comma,list>

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { extractFile } from "@electron/asar";

const HERE = dirname(fileURLToPath(import.meta.url));
const BASELINE = join(HERE, "../baseline/system-paths.json");

// Bundles inside app.asar that carry system-integration code.
const BUNDLES = [".vite/build/index.js", ".vite/build/index.pre.js", ".vite/build/mainView.js"];

// Absolute system paths under these roots are where distro layout diverges.
const PATH_RE = /["'`](\/(?:usr|etc|var|run|opt|lib|lib64|bin|sbin)\/[A-Za-z0-9._/*+-]+)/g;

function extractPaths(payloadDir) {
  const asar = join(payloadDir, "usr/lib/claude-desktop/resources/app.asar");
  const found = new Set();
  for (const rel of BUNDLES) {
    let buf;
    try {
      buf = extractFile(asar, rel);
    } catch {
      continue; // bundle may not exist in a given release; skip
    }
    for (const m of buf.toString("utf8").matchAll(PATH_RE)) found.add(m[1]);
  }
  return [...found].sort();
}

// Rough risk hint for a novel path (Debian layout diverges most under these).
function riskOf(p) {
  if (/^\/usr\/(share|lib|lib64|libexec)\//.test(p)) return "distro-divergent (Debian-specific?)";
  if (/^\/etc\/(apt|apparmor|dpkg)/.test(p)) return "Debian packaging assumption";
  return "review";
}

const payloadDir = process.argv[2];
const arg = process.argv[3];
if (!payloadDir) {
  console.error("usage: check-native-paths.mjs <payloadDir> [version|--update]");
  process.exit(2);
}

const paths = extractPaths(payloadDir);
if (paths.length === 0) {
  console.error("check-native-paths: extracted 0 paths - app.asar layout changed? refusing to proceed");
  process.exit(2);
}

if (arg === "--update") {
  mkdirSync(dirname(BASELINE), { recursive: true });
  writeFileSync(BASELINE, JSON.stringify(paths, null, 2) + "\n");
  console.log(`check-native-paths: wrote ${paths.length} paths to baseline/system-paths.json`);
  process.exit(0);
}

const version = arg || "unknown";
if (!existsSync(BASELINE)) {
  console.error("check-native-paths: baseline/system-paths.json missing - generate it with --update");
  process.exit(2);
}
const allow = new Set(JSON.parse(readFileSync(BASELINE, "utf8")));
const novel = paths.filter((p) => !allow.has(p));

if (novel.length === 0) {
  console.log(`check-native-paths: OK (${paths.length} system paths, all reviewed)`);
  process.exit(0);
}

console.error(`NATIVE-PATH-DRIFT version=${version} paths=${novel.join(",")}`);
console.error("");
console.error("New absolute system path(s) in the upstream bundle, not in the reviewed allowlist:");
for (const p of novel) console.error(`  ${p}   [${riskOf(p)}]`);
console.error("");
console.error("A 'distro-divergent' path is often Debian-only (like the OVMF firmware paths");
console.error("cowork-firmware-paths fixes) and may break Fedora/RHEL/Arch. Review each, then:");
console.error("  - benign / same on all distros -> allowlist it:");
console.error("      node scripts/check-native-paths.mjs <payloadDir> --update   (review the git diff)");
console.error("  - Debian-specific -> write a patch (see patches/cowork-firmware-paths.mjs), then --update");
process.exit(1);
