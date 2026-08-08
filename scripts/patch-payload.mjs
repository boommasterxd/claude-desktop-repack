#!/usr/bin/env node
// Apply the minimal GNOME-Wayland/Cowork patches to an extracted Claude Desktop
// payload, in place. Extract app.asar, patch whichever bundle file under
// `.vite/build/` actually holds each patch's target code, validate, repack
// (keeping native .node modules unpacked), then swap the /usr/bin launcher.
//
// The entry `.vite/build/index.js` has, release to release, been the whole
// bundle, a tiny bootstrap requiring one content-hashed chunk, and (as of
// 1.25927.0) a large file that itself holds plenty of code AND directly
// requires ~100+ sibling `index.chunk-*.js`/`index2.chunk-*.js` chunks - with
// individual patch targets scattered across several of those chunks rather
// than living in one "main" bundle. So instead of resolving a single file to
// patch, each patch is tried against every candidate file (the entry plus
// every local index*.chunk-*.js file); whichever one it matches is where it's
// applied. A patch matching zero files is a real failure; matching more than
// one is ambiguous and also treated as a failure rather than guessed at.
//
// Usage: node scripts/patch-payload.mjs <payloadDir> [version]
//
// On any patch/validation failure it prints a machine-readable line
//   PATCH-FAILURE version=<v> failed=<comma,list>
// and exits 1, so CI can open a per-version issue naming the failing patches.

import { readFileSync, writeFileSync, mkdtempSync, rmSync, existsSync, readdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { extractAll, createPackageWithOptions, getRawHeader } from "@electron/asar";

import { patches as PATCHES } from "../patches/index.mjs";

// Keep in sync with scripts/check-native-paths.mjs's CHUNK_RE: `\d*` covers
// both the `index` and `index2` (and any future `index3`, etc.) chunk groups.
const CHUNK_RE = /^index\d*\.chunk-[\w-]+\.js$/;

const payloadDir = process.argv[2];
const version = process.argv[3] || "unknown";
if (!payloadDir) {
  console.error("usage: patch-payload.mjs <payloadDir> [version]");
  process.exit(2);
}

const fail = (failed) => {
  console.error(`PATCH-FAILURE version=${version} failed=${failed}`);
  process.exit(1);
};

const asarPath = join(payloadDir, "usr/lib/claude-desktop/resources/app.asar");
if (!existsSync(asarPath)) {
  console.error(`patch-payload: app.asar not found at ${asarPath}`);
  fail("layout");
}

const work = mkdtempSync(join(tmpdir(), "cdr-patch-"));
try {
  extractAll(asarPath, work);

  const entryRelPath = ".vite/build/index.js";
  const buildDir = join(work, ".vite/build");
  const chunkRelPaths = readdirSync(buildDir)
    .filter((f) => CHUNK_RE.test(f))
    .map((f) => `.vite/build/${f}`);
  const candidateRelPaths = [entryRelPath, ...chunkRelPaths];

  const codeByFile = new Map(candidateRelPaths.map((rel) => [rel, readFileSync(join(work, rel), "utf8")]));

  // Apply every patch, trying each against every candidate file. Exactly one
  // candidate matching is success; zero or more-than-one is a failure (never
  // guess which file to touch when it's ambiguous).
  const failed = [];
  const touched = new Set();
  for (const p of PATCHES) {
    const hits = [];
    const errors = [];
    for (const rel of candidateRelPaths) {
      try {
        hits.push({ rel, code: p.apply(codeByFile.get(rel)) });
      } catch (e) {
        errors.push(`${rel}: ${e.message}`);
      }
    }
    if (hits.length === 1) {
      codeByFile.set(hits[0].rel, hits[0].code);
      touched.add(hits[0].rel);
      console.log(`  [OK] ${p.name} -> ${hits[0].rel}`);
    } else if (hits.length === 0) {
      failed.push(p.name);
      console.error(`  [FAIL] ${p.name}: no candidate file matched\n    ${errors.join("\n    ")}`);
    } else {
      failed.push(p.name);
      console.error(`  [FAIL] ${p.name}: matched ${hits.length} candidate files (${hits.map((h) => h.rel).join(", ")}) - ambiguous target`);
    }
  }
  if (failed.length) fail(failed.join(","));

  for (const rel of touched) writeFileSync(join(work, rel), codeByFile.get(rel));

  // Syntax-validate every patched file.
  for (const rel of touched) {
    try {
      execFileSync(process.execPath, ["--check", join(work, rel)], { stdio: "pipe" });
      console.log(`  [OK] node --check ${rel}`);
    } catch (e) {
      console.error(`  [FAIL] patched ${rel} has a syntax error:\n${(e.stderr || e.stdout || e.message).toString()}`);
      fail("syntax-check");
    }
  }

  // Repack, keeping native .node modules unpacked (node-pty, claude-native).
  await createPackageWithOptions(work, asarPath, { unpack: "**/*.node" });

  // Verify the unpacked native modules survived the repack.
  const { header } = getRawHeader(asarPath);
  const unpacked = [];
  (function walk(node, p) {
    for (const k in node.files || {}) {
      const f = node.files[k];
      const fp = `${p}/${k}`;
      if (f.unpacked) unpacked.push(fp);
      if (f.files) walk(f, fp);
    }
  })(header, "");
  if (!unpacked.some((f) => f.endsWith(".node"))) fail("unpack-preserve");
  console.log(`  [OK] repacked app.asar (unpacked kept: ${unpacked.join(", ") || "none"})`);

  console.log(`patch-payload: all ${PATCHES.length} patches applied and verified for ${version}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
