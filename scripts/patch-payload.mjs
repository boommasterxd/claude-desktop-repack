#!/usr/bin/env node
// Apply the minimal GNOME-Wayland patches to an extracted Claude Desktop payload,
// in place. Extract app.asar, patch .vite/build/index.js, validate, repack
// (keeping native .node modules unpacked), then swap the /usr/bin launcher.
//
// Usage: node scripts/patch-payload.mjs <payloadDir> [version]
//
// On any patch/validation failure it prints a machine-readable line
//   PATCH-FAILURE version=<v> failed=<comma,list>
// and exits 1, so CI can open a per-version issue naming the failing patches.

import { readFileSync, writeFileSync, mkdtempSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync } from "node:child_process";
import { extractAll, createPackageWithOptions, getRawHeader } from "@electron/asar";

import * as appId from "../patches/quick-entry-app-id.mjs";
import * as toggle from "../patches/quick-entry-cli-toggle.mjs";

const PATCHES = [appId, toggle];

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

  const idxPath = join(work, ".vite/build/index.js");
  let code = readFileSync(idxPath, "utf8");

  // Apply every patch, collecting which ones fail (report them all at once).
  const failed = [];
  for (const p of PATCHES) {
    try {
      code = p.apply(code);
      console.log(`  [OK] ${p.name}`);
    } catch (e) {
      failed.push(p.name);
      console.error(`  [FAIL] ${p.name}: ${e.message}`);
    }
  }
  if (failed.length) fail(failed.join(","));

  writeFileSync(idxPath, code);

  // Syntax-validate the patched main bundle.
  try {
    execFileSync(process.execPath, ["--check", idxPath], { stdio: "pipe" });
    console.log("  [OK] node --check index.js");
  } catch (e) {
    console.error(`  [FAIL] patched index.js has a syntax error:\n${(e.stderr || e.stdout || e.message).toString()}`);
    fail("syntax-check");
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
