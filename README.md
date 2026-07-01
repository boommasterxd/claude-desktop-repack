<div align="center">

# Claude Desktop for Linux <sub>(repack)</sub>

**Anthropic's official Claude Desktop, repackaged for the distros they don't ship,
with signed install repos and automatic updates.**

[![CI](https://github.com/boommasterxd/claude-desktop-repack/actions/workflows/ci.yml/badge.svg)](https://github.com/boommasterxd/claude-desktop-repack/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/endpoint?url=https%3A%2F%2Fboommasterxd.github.io%2Fclaude-desktop-repack%2Fbadges%2Frelease.json)](https://github.com/boommasterxd/claude-desktop-repack/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/boommasterxd/claude-desktop-repack/total?color=7c3aed)](https://github.com/boommasterxd/claude-desktop-repack/releases)
[![License](https://img.shields.io/badge/license-GPL--3.0-blue)](LICENSE)
[![Install page](https://img.shields.io/badge/install-page-7c3aed)](https://boommasterxd.github.io/claude-desktop-repack/)

[**Install page**](https://boommasterxd.github.io/claude-desktop-repack/) &nbsp;·&nbsp; [**Releases**](https://github.com/boommasterxd/claude-desktop-repack/releases) &nbsp;·&nbsp; [**Report a bug**](https://github.com/boommasterxd/claude-desktop-repack/issues/new)

</div>

This repo takes Anthropic's **official Linux `.deb`** and re-wraps it, unmodified
except for a few small [Linux patches](#patches), into every format the other
distros expect, published as a **signed** GitHub Release and served from **signed
install repos** with real `upgrade`-style updates. A scheduled GitHub Action
rebuilds it automatically whenever Anthropic ships a new version, all verified
against one GPG key.

> Not affiliated with or endorsed by Anthropic. Source of truth:
> <https://claude.com/download>.

## Why

Worth using even if an official build already runs on your distro:

- **The formats Anthropic doesn't ship.** They release Linux only as a `.deb` for
  Debian/Ubuntu, so Fedora, RHEL, openSUSE, Arch, NixOS and portable AppImage users
  are left out. This fills every gap, with signed repos and automatic updates.
- **GNOME-on-Wayland fixes that help everyone, including Debian/Ubuntu.** Two of the
  patches fix bugs the *official* build has on GNOME Wayland on **any** distro: the
  global **Quick Entry hotkey** (broken by a Chromium portal bug) works again via a
  socket + `claude-desktop-hotkey`, and the transparent **Quick Entry overlay** gets
  its own `WM_CLASS` so shell extensions can exclude just it without touching the
  main window.
- **Cowork on non-Debian distros.** Two more patches fix the VM firmware-path lookup
  and the dependency-install hint so Cowork works on Fedora / Arch / openSUSE too.

See [Patches](#patches) for the details on all four.

> **Scope:** this ships the app **as Anthropic ships it**, plus the small
> functional fixes above; it deliberately does **not** unlock features Anthropic
> gates off on Linux.
>
> If you want the **full experience**, definitely check out
> [**patrickjaja/claude-desktop-bin**](https://github.com/patrickjaja/claude-desktop-bin):
> it patches a whole set of Linux-only extras to life, including **Computer Use**,
> **custom themes**, **multiple side-by-side profiles**, **Recent Projects**,
> **Open in VS Code / Cursor / Zed**, Hardware Buddy, Dispatch and more.
>
> Huge thanks to [**@patrickjaja**](https://github.com/patrickjaja) for that
> excellent work, which paved the way for this project. Go give it a look and a star.

---

## Install

The recommended way is a **signed repo with automatic updates**. All one-liners are
also on the [install page](https://boommasterxd.github.io/claude-desktop-repack/).

### Fedora / RHEL / openSUSE <sub>(dnf / zypper)</sub>

```bash
sudo dnf config-manager --add-repo https://boommasterxd.github.io/claude-desktop-repack/rpm/claude-desktop-repack.repo
sudo dnf install claude-desktop-repack        # then: sudo dnf upgrade
```

### Arch / Manjaro / EndeavourOS <sub>(pacman)</sub>

```bash
curl -fsSL https://boommasterxd.github.io/claude-desktop-repack/RELEASE-PUBKEY.asc | sudo pacman-key --add -
sudo pacman-key --lsign-key 2874A3CDE4A67DD1
# append to /etc/pacman.conf:
#   [claude-desktop-repack]
#   SigLevel = Required
#   Server = https://boommasterxd.github.io/claude-desktop-repack/arch/$arch
sudo pacman -Sy claude-desktop-repack
```

### Debian / Ubuntu <sub>(apt)</sub>

```bash
curl -fsSL https://boommasterxd.github.io/claude-desktop-repack/RELEASE-PUBKEY.asc | gpg --dearmor | sudo tee /usr/share/keyrings/claude-desktop-repack.gpg >/dev/null
echo "deb [signed-by=/usr/share/keyrings/claude-desktop-repack.gpg] https://boommasterxd.github.io/claude-desktop-repack/deb stable main" | sudo tee /etc/apt/sources.list.d/claude-desktop-repack.list
sudo apt update && sudo apt install claude-desktop-repack
```

Anthropic's [official apt repo](https://code.claude.com/docs/en/desktop-linux) is
also a fine choice on Debian/Ubuntu.

### AppImage <sub>(any glibc distro, self-updating)</sub>

Download the `.AppImage` from the [latest release](https://github.com/boommasterxd/claude-desktop-repack/releases/latest),
`chmod +x`, and run it. Add it to [GearLever](https://github.com/mijorus/gearlever)
and it updates itself via the embedded `zsync` info, downloading only the changed
blocks, never the whole file again.

### Nix / NixOS <sub>(flake)</sub>

```bash
NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure github:boommasterxd/claude-desktop-repack
# or: inputs.claude-desktop-repack.url = "github:boommasterxd/claude-desktop-repack";
```

### Direct download

Every format is also a plain [release asset](https://github.com/boommasterxd/claude-desktop-repack/releases/latest):

```bash
sudo dnf install ./claude-desktop-repack-*.x86_64.rpm                       # rpm
sudo pacman -U ./claude-desktop-repack-*-x86_64.pkg.tar.zst                 # arch
sudo apt install ./claude-desktop-repack_*_amd64.deb                        # deb
chmod +x claude-desktop-repack-*-x86_64.AppImage && ./claude-desktop-repack-*-x86_64.AppImage
tar xzf claude-desktop-repack-*-linux.tar.gz && ./claude-desktop-repack-*/claude-desktop
```

## Verify

Every release ships `RELEASE-PUBKEY.asc` + `SHA256SUMS.txt.asc`; the rpm packages
and all repo metadata are GPG-signed with the same key.

```bash
gpg --import RELEASE-PUBKEY.asc
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt && sha256sum -c SHA256SUMS.txt
```

## What it repackages

| Format | Arches | For |
|--------|--------|-----|
| **RPM** + dnf repo | x86_64, aarch64 | Fedora / RHEL / openSUSE |
| **pacman** `.pkg.tar.zst` + repo | x86_64, aarch64 | Arch / Manjaro / EndeavourOS |
| **.deb** + apt repo | amd64, arm64 | Debian / Ubuntu |
| **AppImage** + `.zsync` | x86_64, aarch64 | any glibc distro |
| **tarball** | x86_64, aarch64 | generic / portable |
| **Nix flake** | x86_64, aarch64 | NixOS / Nix |

Package name: `claude-desktop-repack` (so `dnf`/`apt`/`pacman` show it as ours);
app identity (binary, `.desktop`, icon, WM_CLASS, `claude://` handler) stays
`claude-desktop`, indistinguishable from the official build.

## Versions

What each channel currently serves, updated automatically on every release. Each
distro badge reads the version recorded in **that repo's own metadata**, so it also
confirms the signed repo actually carries the latest build:

| Channel | Version |
|---------|---------|
| GitHub release | [![release](https://img.shields.io/endpoint?url=https%3A%2F%2Fboommasterxd.github.io%2Fclaude-desktop-repack%2Fbadges%2Frelease.json)](https://github.com/boommasterxd/claude-desktop-repack/releases/latest) |
| Fedora / RHEL / openSUSE <sub>(dnf)</sub> | [![dnf](https://img.shields.io/endpoint?url=https%3A%2F%2Fboommasterxd.github.io%2Fclaude-desktop-repack%2Fbadges%2Ffedora.json)](#fedora--rhel--opensuse-dnf--zypper) |
| Arch / Manjaro / EndeavourOS <sub>(pacman)</sub> | [![pacman](https://img.shields.io/endpoint?url=https%3A%2F%2Fboommasterxd.github.io%2Fclaude-desktop-repack%2Fbadges%2Farch.json)](#arch--manjaro--endeavouros-pacman) |
| Debian / Ubuntu <sub>(apt)</sub> | [![apt](https://img.shields.io/endpoint?url=https%3A%2F%2Fboommasterxd.github.io%2Fclaude-desktop-repack%2Fbadges%2Fdebian.json)](#debian--ubuntu-apt) |

These are shields **endpoint** badges reading small JSON files from our own Pages
site, so they never hit a GitHub API rate limit and can't get stuck on a stale
"invalid" image the way a live query can.

## Patches

The only changes to the app are a few small patches applied to `app.asar` at build
time by `scripts/patch-payload.mjs` (regex on the minified `index.js`). The
Electron binary and native modules are never touched. If a patch ever stops
matching after an upstream change, the build fails and opens an issue naming the
patch, so a broken patch is never shipped silently.

Two of them (`quick-entry-cli-toggle`, `quick-entry-app-id`) address gaps specific
to **GNOME on Wayland**; on X11 and other compositors the official build already
behaves correctly. Two more (`cowork-firmware-paths`, `cowork-install-hint`) make
Cowork work and its dependency hint correct on non-Debian distros. The app itself
runs unmodified everywhere; these only fill in the Linux/distro gaps the official
Debian build leaves.

### Quick Entry hotkey (`quick-entry-cli-toggle`)

The official build's global Quick Entry hotkey does not work on GNOME Wayland: it
goes through Chromium's GlobalShortcuts portal, which is broken for non-sandboxed
apps on `xdg-desktop-portal` 1.20+ (see
[electron/electron#51875](https://github.com/electron/electron/issues/51875)).

This patch exposes the app's own Quick Entry toggle over a Unix socket. The
packages ship a small `claude-desktop-hotkey` command next to the (untouched)
upstream launcher; it pokes that socket to open/close Quick Entry in ~5-25 ms.
Bind it to a native GNOME shortcut:

```bash
claude-desktop-hotkey --install       # binds Ctrl+Alt+Space
# custom key: CLAUDE_QE_ACCEL='<Super>space' claude-desktop-hotkey --install
# remove:     claude-desktop-hotkey --uninstall
```

(`claude-desktop-hotkey` is installed in `PATH` by the RPM and `.deb`. Running it
with no arguments toggles Quick Entry; pressing the bound key does the same.)

### Quick Entry window name (`quick-entry-app-id`)

The Quick Entry window is a transparent, frameless overlay: only the small input
pill is drawn, the rest of the window is transparent. GNOME extensions that add
rounded corners and a drop shadow (**Rounded Window Corners Reborn**, Unite, ...)
paint an opaque rounded rectangle behind *every* window. On the transparent Quick
Entry that rectangle shows through, so instead of just the pill you see a large
opaque box with the pill floating in its corner.

Those extensions can exclude windows by `WM_CLASS` / Wayland `app_id`, but
Electron assigns one app_id per process, so the main Claude window and the Quick
Entry window both report `claude` and cannot be told apart, you would have to
disable the effect on the main window too.

This patch gives the Quick Entry window its **own** `WM_CLASS`,
`claude-quick-entry`, so you can exclude just it. In **Rounded Window Corners
Reborn**: open its settings, go to **Blacklist**, and add:

```
claude-quick-entry
```

The main Claude window keeps its rounded corners and shadow; only the transparent
Quick Entry overlay is excluded. Other extensions (Unite, Blur my Shell, ...)
have the same kind of per-`WM_CLASS` blacklist.

### Cowork VM firmware paths (`cowork-firmware-paths`)

Cowork runs its agent workspace inside a QEMU/KVM VM that needs OVMF (UEFI)
firmware and `virtiofsd`. The official Debian `.deb` hard-codes Debian-only paths
(`/usr/share/OVMF/...`, `/usr/{libexec,bin}/virtiofsd`), so on distros that ship
the firmware elsewhere the VM capability probe returns **unsupported** and the
Cowork Download button stays inert.

This patch appends the non-Debian search paths (Fedora/RHEL
`/usr/share/edk2/ovmf/`, Arch `/usr/share/edk2/x64/`, plus `/usr/lib/virtiofsd`)
to the probe's candidate lists. Debian paths are kept first, so Debian/Ubuntu
behaviour is byte-for-byte unchanged. You still need the VM dependencies
installed:

```bash
# Fedora / RHEL
sudo dnf install qemu-kvm edk2-ovmf virtiofsd
# Arch
sudo pacman -S qemu-full edk2-ovmf virtiofsd
```

Notes: on x86_64 Fedora a compatibility symlink at `/usr/share/OVMF/` often makes
Cowork work even without this patch, but Arch, arm64 and others need it. openSUSE
(firmware named `*-code.bin`) needs a different VARS-file rule and is a known gap.

### Cowork dependency hint (`cowork-install-hint`)

When those Cowork dependencies are missing, the app shows a copy-paste install
command. Upstream hard-codes the Debian one (`sudo apt install ...` with Debian
package names), which is wrong on other distros. This patch wraps it in a tiny
runtime translator: on Debian/Ubuntu it is returned unchanged, otherwise the first
of `dnf`/`pacman`/`zypper` found rewrites the manager and package names for that
distro. Cosmetic and fully guarded: any failure falls back to the original string.

## Contributing

Contributions are welcome. Build the packages locally into `./dist`:

```bash
npm ci                                   # once: installs @electron/asar
bash scripts/build-local.sh              # all formats, host arch
bash scripts/build-local.sh amd64 rpm    # just one format/arch
```

`build-deb.sh` needs `dpkg-deb` (on Fedora: `sudo dnf install dpkg`);
`build-appimage.sh` needs `zsync`/`zsyncmake`, and on FUSE-less machines
`APPIMAGE_EXTRACT_AND_RUN=1`. Building locally (no `GITHUB_REPOSITORY` set) skips
the AppImage update-info and `.zsync`, which is expected.

### Writing a patch

A patch is a small ES module in `patches/` that exports `name`, `description`, and
`apply(code) -> code`. It is auto-discovered by `patches/index.mjs`, applied by
`scripts/patch-payload.mjs`, then the result is run through `node --check`, so
there is nothing else to wire up:

```js
// patches/my-fix.mjs
export const name = "my-fix";
export const description = "one line, shown in the release notes";

export function apply(code) {
  const pattern = /("some-stable-string-literal":)([\w$]+)/g;      // see rules below
  const matches = [...code.matchAll(pattern)];
  if (matches.length !== 1) {                                       // exactly one
    throw new Error(`my-fix: expected 1 match, found ${matches.length}`);
  }
  const out = code.replace(pattern, (_m, key, id) => `${key}patched_${id}`);
  if (!out.includes("patched_")) {                                 // assert result
    throw new Error("my-fix: injection marker missing after replace");
  }
  return out;
}
```

The patches run as regex over Anthropic's **minified** `index.js`, so every
upstream release can rename every local identifier and re-shuffle the code. The
whole difficulty is writing a match that still hits **exactly the one** spot you
mean after a re-minify, and fails loudly the moment it no longer does. Rules that
make that hold:

- **Match exactly one occurrence.** Collect all matches (`[...code.matchAll(re)]`)
  and `throw` unless there is exactly `1`. A pattern that quietly matches 0 (silent
  no-op) or 2+ (patches an unrelated site) is the main way these break. Never use a
  bare `.replace()` whose success you don't count.
- **Never hardcode a minified name; match it with `[\w$]+`.** Minified identifiers
  are short, unstable, and can contain `$` (e.g. `F$e`, `$S`) - bare `\w+` silently
  fails to match those. Capture the name and reuse it in the replacement instead of
  assuming what it is.
- **Anchor only on things upstream is unlikely to rename.** String literals, public
  API / property / method names (`getPrimaryDisplay`, `app_id`, socket paths),
  enum members, error messages. Do **not** anchor on the exact expression shape,
  variable order, or whitespace unless the structure is genuinely required for the
  injection - that is exactly what re-minification perturbs.
- **Keep the pattern as short and specific as possible.** Match the smallest slice
  that uniquely identifies the site. Long literal runs of minified code are brittle;
  a couple of stable anchors plus `[\w$]+` bridges are not. Prefer a narrow context
  over a broad one, so you don't accidentally become non-unique on the next release.
- **Assert your end-state after replacing.** Check the injected marker (or the
  behaviour you guarantee) is actually present in the output and `throw` if not.
  "The old pattern is gone" is **not** proof the new behaviour is in - those diverge
  the instant upstream refactors. Verify the thing you added, not the absence of the
  thing you removed.
- **Fail loud, never guess.** On any mismatch `throw`. `patch-payload.mjs` prints
  `PATCH-FAILURE version=<v> failed=<name>` and exits 1, which fails CI and (in the
  release workflow) opens a per-version issue naming your patch. A broken patch is
  never shipped silently - a loud failure is the desired outcome, not something to
  paper over with a `try/catch` or an "already patched" shortcut.

To pull the current minified bundle out of a fetched payload and iterate against
the real code:

```bash
node -e 'const a=require("@electron/asar"); require("fs").writeFileSync("/tmp/index.js", a.extractFile("PAYLOAD/usr/lib/claude-desktop/resources/app.asar", ".vite/build/index.js"))'
```

Add a `### ...` subsection to the [Patches](#patches) section above so the change is
documented for users.

### Opening a PR

PRs target `main`, which is protected: the `CI` and `gitleaks` checks must pass
before merge. Use [Conventional Commit](https://www.conventionalcommits.org) titles
(`fix(patches): ...`, `feat: ...`, `docs: ...`) - PRs are squash-merged, so the PR
title becomes the commit on `main` and drives the grouped release-notes changelog.
