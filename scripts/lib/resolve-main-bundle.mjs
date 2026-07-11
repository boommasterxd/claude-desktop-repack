// Vite's `.vite/build/index.js` entry can either be the whole Electron
// main-process bundle, or (as of Claude Desktop 1.19367.0) a tiny bootstrap
// that just `require()`s a separately content-hashed chunk, e.g.
// `index.chunk-CNXUb5h4.js`, which then holds the actual code. The hash
// changes every build, so nothing may hardcode the chunk filename.
//
// This follows that require so patches and the path-drift scan always
// inspect wherever the real code lives, whether upstream currently ships a
// single-file bundle or a split one.

const CHUNK_REQUIRE_RE = /require\("\.\/(index\.chunk-[\w-]+\.js)"\)/g;

// entryRelPath: the asar-relative path of `.vite/build/index.js`.
// entryCode: that file's contents.
// Returns the asar-relative path to patch/scan: the resolved chunk if the
// entry is a bootstrap, or entryRelPath unchanged if it is the bundle itself.
export function resolveMainBundleRelPath(entryRelPath, entryCode) {
  const matches = [...entryCode.matchAll(CHUNK_REQUIRE_RE)];
  if (matches.length === 0) return entryRelPath;
  if (matches.length > 1) {
    throw new Error(
      `resolve-main-bundle: expected at most 1 local index.chunk-*.js require in ${entryRelPath}, found ${matches.length}`,
    );
  }
  const dir = entryRelPath.includes("/") ? entryRelPath.slice(0, entryRelPath.lastIndexOf("/") + 1) : "";
  return `${dir}${matches[0][1]}`;
}
