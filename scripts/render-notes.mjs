#!/usr/bin/env node
// Render the GitHub release notes from packaging/release-notes.md.tmpl, filling
// in the version, the repo, and the list of patches that were applied (read from
// patches/index.mjs) so the changelog always names exactly the applied patches.
//
// Usage: node scripts/render-notes.mjs <version> <owner/repo>

import { readFileSync } from "node:fs";
import { patches } from "../patches/index.mjs";

const [, , version = "unknown", repo = ""] = process.argv;

const list = patches
  .map((p) => `- \`${p.name}\` ${p.description || ""}`.trimEnd())
  .join("\n");

const tmpl = readFileSync(new URL("../packaging/release-notes.md.tmpl", import.meta.url), "utf8");
process.stdout.write(
  tmpl
    .replaceAll("__VERSION__", version)
    .replaceAll("__REPO__", repo)
    .replace("__PATCHES__", list),
);
