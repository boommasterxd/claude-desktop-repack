# CLAUDE.md

Guidance for working on **claude-desktop-repack**. Read this before making changes.
Everything in this repo (code, comments, docs, commits) is in English; the user
of the app never sees any of it, only Anthropic's own untouched UI strings.

## What this repo is

It repackages Anthropic's **official** Claude Desktop Linux build (shipped only as
a `.deb` for Debian/Ubuntu) into the formats it is not offered in: **RPM**, **.deb**
(rebuilt), **tarball**, **AppImage** (`+ .zsync`), an **Arch** `.pkg.tar.zst`, and a
**Nix** flake, for x86_64 and aarch64. It applies a few small patches to the app's
`app.asar` (two GNOME-Wayland Quick Entry fixes + two Cowork cross-distro fixes);
otherwise the app is a faithful repackage. The Electron binary is never touched.

A scheduled GitHub Action watches upstream and publishes a signed GitHub Release
for each new version. Distribution is **GitHub Releases only** (no AUR, no apt/dnf
repo). Not affiliated with Anthropic. Source of truth: <https://claude.com/download>.

### Names: package vs. app identity

Two names on purpose, do not conflate them:

- **Package name is `claude-desktop-repack`** so `dnf`/`apt`/`rpm -q` show it as
  ours and it never collides with `claude-desktop-bin` or a manual install. The
  package `Provides:`/`Conflicts:` the plain `claude-desktop` so the two cannot
  coexist.
- **App identity stays `claude-desktop`**: the binary, `/usr/bin/claude-desktop`,
  the `.desktop` file, the icon, the WM_CLASS and the `claude://` handler all keep
  the upstream name so the desktop integration is indistinguishable from official.

## The pipeline (`.github/workflows/release.yml`)

One workflow, four jobs:

1. **detect** (cron every 3h + manual `workflow_dispatch`): reads the latest
   upstream version from Anthropic's apt index (`scripts/detect-version.sh`),
   derives the packaging revision (`pkgrel`), and decides whether to build.
2. **build** (matrix `amd64` / `arm64`): fetches + SHA256-verifies the official
   `.deb`, patches it, and builds all packaged formats (RPM, deb, tarball,
   AppImage, Arch). Uploads them as artifacts. (Nix is a repo flake, not a CI build.)
3. **release**: collects the artifacts, signs them, renders the notes, and
   publishes/updates the GitHub Release `v<fullver>`.
4. **notify-failure** (`if: failure()`): opens a GitHub issue with the failing
   jobs' logs. A patch mismatch gets a **per-version** issue naming the patch.

### Versioning and state (nothing committed back)

Releases are tagged **`v<upstream>-<pkgrel>`** (e.g. `v1.17377.1-0`). The packaging
revision `pkgrel` is **derived from the published releases**, not stored in a file:

- New upstream version (no `v<version>-<N>` release yet) -> `-0`, build.
- `force: true` on an already-released version -> `-(highest N + 1)`, build.
- Already released and not forced -> nothing to do.

So the "state" is the set of published GitHub Releases; the workflow has
`contents: write` only to create releases and **never commits or pushes** to the
repo (which is protected anyway). The `pkgrel` flows into the RPM `Release`, the
deb revision, and the tarball/AppImage filenames, so a fix rebuild is a real
**upgrade** for `dnf`/`apt`.

### The `force` input

`force` is a boolean on the manual run only (the cron never sets it). It means
"rebuild the current upstream version as the **next** packaging revision `-(N+1)`".
Without it, the workflow only builds genuinely new upstream versions. `force` does
not replace the current release; it publishes a new `-N` alongside it (the old one
stays; delete it by hand if you want to declutter).

### The patch step

`scripts/fetch-deb.sh` downloads the official `.deb`, verifies its SHA256 against
the apt index, extracts the payload, and calls **`scripts/patch-payload.mjs`**,
which:

1. unpacks `app.asar` (`@electron/asar`),
2. applies every patch in `patches/` (see below),
3. runs `node --check` on the patched `index.js`,
4. repacks, keeping native `.node` modules unpacked (`unpack: "**/*.node"`).

It then drops the `claude-desktop-hotkey` helper next to the **untouched** upstream
`/usr/bin/claude-desktop` symlink. The asar-integrity fuse is a no-op on Linux
(verified: a repacked copy launches), so no fuse flip or hash re-embed is needed.

## Layout

```
patches/*.mjs         the patches; patches/index.mjs auto-discovers them
scripts/
  detect-version.sh   highest upstream version from the apt index
  fetch-deb.sh        download + SHA256-verify + extract + guard + call patch-payload
  check-native-paths.mjs  fail if a new, unreviewed absolute system path appears
  patch-payload.mjs   unpack asar -> apply patches -> node --check -> repack
  build-rpm.sh        \
  build-deb.sh         |  one format each; all honour $PKGREL and $ARCH
  build-tarball.sh     |  build-arch.sh builds .pkg.tar.zst via makepkg in an
  build-appimage.sh    |  archlinux container (reuses the tarball; aarch64 via
  build-arch.sh       /   CARCH override, no qemu)
  build-local.sh      local wrapper around the format build scripts
  sign-artifacts.sh   RPM signature + SHA256SUMS.txt(.asc)
  render-notes.mjs    fills packaging/release-notes.md.tmpl
  render-pkgbuild.sh  fills packaging/arch/PKGBUILD.in for the release-attached PKGBUILD
  bump-nix-pin.sh     opens (+ auto-merges) a PR bumping packaging/nix/package.nix each release
  changelog.mjs       grouped conventional-commit changelog for a git range
packaging/
  rpm/claude-desktop-repack.spec    the RPM spec (Release: %{_pkgrel}%{?dist})
  arch/PKGBUILD.in + *.install      Arch PKGBUILD template + install scriptlet
  nix/package.nix     Nix derivation (release-coupled: fetches this repo's release
                                    tarball, autoPatchelfs the bundled Electron)
  launcher/claude-desktop-hotkey    Quick Entry hotkey helper (socket poker)
  release-notes.md.tmpl             notes template (__VERSION__ __REPO__ __PATCHES__)
flake.nix             Nix flake exposing the package for x86_64/aarch64-linux
RELEASE-PUBKEY.asc    public half of the signing key
```

## Patches

The patches live in `patches/` and restore Linux behaviour the official build
lacks: two GNOME-Wayland Quick Entry fixes (on X11 upstream is already fine) plus
two Cowork cross-distro fixes (firmware paths, install hint). Each
module exports `name`, `apply(code) -> code`, and `description`. `patches/index.mjs`
`readdir`s the folder, imports every `*.mjs` except itself, and throws if a module
lacks `name`+`apply`. See `README.md` (Patches section) for the user-facing story.

- **`quick-entry-cli-toggle`** exposes the Quick Entry toggle over a Unix socket
  (Chromium's GlobalShortcuts portal is broken on GNOME Wayland,
  electron/electron#51875). The shipped `claude-desktop-hotkey` command + a native
  GNOME shortcut drive it.
- **`quick-entry-app-id`** gives the Quick Entry window its own WM_CLASS
  (`claude-quick-entry`) so corner/shadow extensions can exclude just it.

### Patch conventions (important, this is the fragile part)

Patches are regex over the minified `index.js`, so they are version-sensitive.
Every upstream release can rename every minified identifier. Follow these rules:

- Use `[\w$]+` (never bare `\w+`, and never a hardcoded name) for minified
  identifiers, because they can contain `$`.
- Anchor on things upstream is unlikely to change: string literals, external
  API/property names, enum member names. Do not anchor on the exact expression
  shape unless it is structurally required for the injection.
- Require **exactly one match** per pattern, and after patching assert the
  injected markers are present. On any mismatch, **throw** (fail loud), never
  patch silently and never guess.
- `patch-payload.mjs` prints `PATCH-FAILURE version=<v> failed=<list>` and exits 1
  on any failure, which makes `notify-failure` open the per-version issue. A broken
  patch is therefore never shipped.
- Separately, `check-native-paths.mjs` runs before patching and prints
  `NATIVE-PATH-DRIFT version=<v> paths=<list>` (exit 1) when the bundle gains a new
  absolute system path not in `baseline/system-paths.json` - a possibly Debian-only
  path that could break non-Debian distros. `notify-failure` opens a `path-drift`
  issue. Allowlist benign paths with `--update`, or write a patch (like
  `cowork-firmware-paths`) for Debian-specific ones.

## How to do things

### Build locally

```bash
npm ci                                # once: installs @electron/asar
bash scripts/build-local.sh           # all formats, host arch, into ./dist
bash scripts/build-rpm.sh amd64 dist  # a single format/arch directly
PKGREL=1 bash scripts/build-rpm.sh amd64 dist   # simulate a fix revision
```

`build-deb.sh` needs `dpkg-deb` (Fedora: `dnf install dpkg`). `build-appimage.sh`
needs `zsync`/`zsyncmake` and, on FUSE-less machines, `APPIMAGE_EXTRACT_AND_RUN=1`.
Locally (no `GITHUB_REPOSITORY`) the AppImage is built without update info and the
`.zsync` is skipped, that is expected.

### Add a patch

Drop a module into `patches/` that exports `name`, `apply(code)` and (optional)
`description`. It is auto-discovered, applied, validated, and listed in the release
notes. Nothing else to wire. Add a `### ...` subsection to `README.md` for humans.

### Ship a packaging fix (same upstream version)

Merge the fix, then run the workflow manually with **`force: true`**. It publishes
the next revision `v<version>-<N+1>`, which `dnf`/`apt` treat as an upgrade.

### A patch broke after an upstream release

The build fails and `notify-failure` opens "Patch validation failed: Claude
Desktop <version>" naming the patch. Extract the current `index.js` and re-check
the pattern, then fix `patches/<name>.mjs`, open a PR, and after merge run the
workflow with `force: true`. To pull the current minified bundle out of a fetched
payload:

```bash
node -e 'const a=require("@electron/asar"); require("fs").writeFileSync("/tmp/index.js", a.extractFile("PAYLOAD/usr/lib/claude-desktop/resources/app.asar", ".vite/build/index.js"))'
```

### Signing

Releases are signed with the key whose public half is `RELEASE-PUBKEY.asc`. The
private key is the `GPG_PRIVATE_KEY` Actions secret (`GPG_PASSPHRASE` optional).
`scripts/sign-artifacts.sh` embeds the RPM signature and writes
`SHA256SUMS.txt.asc`. Without the secret, builds still succeed unsigned.
**This key is this repo's own; do not reuse any other project's release key.**

## Conventions

### Commits (Conventional Commits)

`type(scope): description`, English, imperative mood. **The type drives the grouped
release-notes changelog** (`scripts/changelog.mjs`), so choose it deliberately:

| type | changelog group |
|------|-----------------|
| `feat` | Features |
| `fix` | Bug fixes |
| `perf`, `refactor` | Improvements |
| `docs` | Documentation |
| `chore`, `ci`, `build`, `test`, `style` | Maintenance |
| anything else | Other |

Examples: `feat(patches): add quick-entry blur guard`,
`fix(build-appimage): generate the zsync file explicitly`,
`ci: pin actions by commit sha`. PRs are **squash-merged**, so the **PR title** also
must follow this convention (it becomes the commit that lands on `main`).

### Working on the repo

- `main` is protected: all changes go through a PR and the `gitleaks` check must
  pass. Do not commit or push directly to `main`.
- Do not merge PRs on the maintainer's behalf unless explicitly asked; open the PR
  and stop.
- The release workflow is read-only on the repo (it only publishes Releases).
