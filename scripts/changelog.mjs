#!/usr/bin/env node
// Print a grouped "Packaging changes" changelog for a git range, grouping our
// commits by conventional-commit type (feat/fix/...). Prints nothing if the
// range is empty.
//
// Usage: node scripts/changelog.mjs <range>   e.g. v1.17377.1-0..HEAD
//
// The release workflow's Nix-pin bump only lands on main once its PR's
// auto-merge completes (after gitleaks runs) - after this release's notes are
// already rendered - so its commit would otherwise show up misattributed to
// the *next* release's changelog instead of this one. We skip
// "chore(nix): bump flake pin to ..." commits here and let the workflow
// inject a correctly-attributed entry via NIX_BUMP_FULLVER once it knows the
// bump actually happened (see the "Note the Nix pin bump" step).

import { execFileSync } from "node:child_process";

const range = process.argv[2];
const nixBumpFullver = process.env.NIX_BUMP_FULLVER || "";

let raw = "";
try {
  const args = ["log", "--no-merges", "--pretty=format:%s%x09%h"];
  if (range) args.push(range);
  raw = execFileSync("git", args, { encoding: "utf8" });
} catch {
  raw = "";
}

const GROUPS = [
  ["Features", ["feat"]],
  ["Bug fixes", ["fix"]],
  ["Improvements", ["perf", "refactor"]],
  ["Documentation", ["docs"]],
  ["Maintenance", ["chore", "ci", "build", "test", "style"]],
];

const buckets = new Map(GROUPS.map(([title]) => [title, []]));
const other = [];

for (const line of raw.split("\n").filter(Boolean)) {
  const [subject, hash] = line.split("\t");
  if (/^chore\(nix\): bump flake pin to /.test(subject)) continue;
  const m = subject.match(/^(\w+)(?:\([^)]*\))?!?:\s*(.+)$/);
  const grp = m && GROUPS.find(([, types]) => types.includes(m[1].toLowerCase()));
  if (grp) buckets.get(grp[0]).push(`- ${m[2]} (${hash})`);
  else other.push(`- ${subject} (${hash})`);
}

if (nixBumpFullver) {
  buckets.get("Maintenance").push(`- bump Nix flake pin to ${nixBumpFullver}`);
}

const out = [];
for (const [title] of GROUPS) {
  const items = buckets.get(title);
  if (items.length) out.push(`### ${title}`, "", ...items, "");
}
if (other.length) out.push("### Other", "", ...other, "");

if (out.length) {
  process.stdout.write("## Packaging changes\n\n" + out.join("\n") + "\n");
}
