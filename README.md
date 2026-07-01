# claude-desktop-repack

Repackages Anthropic's official Claude Desktop Linux build into the formats it
is not shipped in, so distributions Anthropic does not target can install it too.

## Why

Anthropic ships Claude Desktop for Linux only as a `.deb` for Debian/Ubuntu (via
their apt repository). There is no native RPM, AppImage or tarball, so Fedora,
RHEL, openSUSE and others are left out.

This repo takes the **official `.deb`** and re-wraps it into:

- **RPM** (x86_64, aarch64) for Fedora / RHEL / openSUSE
- **AppImage** + `.zsync` (x86_64, aarch64) for any glibc distro
- **tarball** (x86_64, aarch64), generic and portable
- **.deb** (amd64, arm64), rebuilt for parity (on Debian/Ubuntu prefer the
  [official apt repo](https://code.claude.com/docs/en/desktop-linux) for updates)

A scheduled GitHub Action watches Anthropic's apt index and publishes a new
signed GitHub Release whenever upstream releases a new version. The only change
to the app is two small GNOME-Wayland patches (see [Patches](#patches) below);
everything else is a faithful repackage.

> Not affiliated with or endorsed by Anthropic. Source of truth:
> <https://claude.com/download>.

## Install

Grab the file for your distro and architecture from [Releases](../../releases):

```bash
# Fedora / RHEL / openSUSE
sudo dnf install ./claude-desktop-repack-*.x86_64.rpm

# Portable (any distro)
chmod +x claude-desktop-repack-*-x86_64.AppImage && ./claude-desktop-repack-*-x86_64.AppImage
```

Optional verification (each release ships `RELEASE-PUBKEY.asc` + `SHA256SUMS.txt.asc`):

```bash
gpg --import RELEASE-PUBKEY.asc
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt && sha256sum -c SHA256SUMS.txt
```

## Patches

The only changes to the app are two small patches applied to `app.asar` at build
time by `scripts/patch-payload.mjs` (regex on the minified `index.js`). The
Electron binary and native modules are never touched. If a patch ever stops
matching after an upstream change, the build fails and opens an issue naming the
patch, so a broken patch is never shipped silently.

Both address gaps specific to **GNOME on Wayland**; on X11 and other compositors
the official build already behaves correctly.

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

## Maintaining

- **Add a patch:** drop a module into `patches/` that exports `name`, `apply(code)`
  and (optional) `description`. It is applied by the build, listed in the release
  notes, and validated automatically (a non-matching patch fails the build and
  files an issue). Nothing else to wire.
- **Ship a packaging fix** for the same upstream version (e.g. after fixing a
  patch): merge the fix, then run the workflow with **`force: true`**. It
  publishes the next revision `v<version>-<N>` (RPM `Release`, deb revision),
  which package managers see as an upgrade. A new upstream version starts at
  `-0` again. The revision is derived from the published releases, nothing to
  edit.
- Release notes are generated: the patch list from `patches/`, plus a changelog
  of your commits since the previous release, grouped by conventional-commit type.
