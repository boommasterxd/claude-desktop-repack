#!/usr/bin/env node
// Apply every patch in <patchesDir> to <targetFile>, in place. Used by the Nix
// build (which cannot run the full patch-payload.mjs pipeline conveniently) to
// patch the extracted app.asar's index.js. The patch modules are dependency-free
// (pure string/regex apply(code)), so plain node suffices - no @electron/asar.
//
// Usage: node apply-patches.mjs <targetFile> <patchesDir>
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { pathToFileURL } from "node:url";
import { join } from "node:path";

const [, , target, patchesDir] = process.argv;
if (!target || !patchesDir) {
  console.error("usage: apply-patches.mjs <targetFile> <patchesDir>");
  process.exit(2);
}

const files = readdirSync(patchesDir)
  .filter((f) => f.endsWith(".mjs") && f !== "index.mjs")
  .sort();
if (files.length === 0) {
  console.error("apply-patches: no patch modules found - refusing to proceed");
  process.exit(2);
}

let code = readFileSync(target, "utf8");
for (const f of files) {
  const mod = await import(pathToFileURL(join(patchesDir, f)).href);
  if (typeof mod.apply !== "function") {
    console.error(`apply-patches: ${f} has no apply() export`);
    process.exit(1);
  }
  code = mod.apply(code);
  process.stderr.write(`[nix-patch] applied ${mod.name || f}\n`);
}
writeFileSync(target, code);
process.stderr.write(`[nix-patch] ${files.length} patches applied to ${target}\n`);
