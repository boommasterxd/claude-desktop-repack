// Auto-discovering patch registry: every `*.mjs` in this folder (except this
// file) is loaded as a patch. To add a patch, just drop a new module here that
// exports `name`, `apply(code) -> code`, and (optional) `description`. Nothing
// else to edit: the build applies it and the release notes list it.
//
// Patches run in filename order. If order ever matters, prefix the files
// (e.g. `10-foo.mjs`, `20-bar.mjs`).

import { readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

const files = readdirSync(here)
  .filter((f) => f.endsWith(".mjs") && f !== "index.mjs")
  .sort();

export const patches = [];
for (const file of files) {
  const mod = await import(`./${file}`);
  if (typeof mod.apply !== "function" || !mod.name) {
    throw new Error(`patches/${file}: a patch module must export \`name\` and \`apply\``);
  }
  patches.push(mod);
}
