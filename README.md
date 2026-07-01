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
to the app is two small GNOME-Wayland fixes (see
[Quick Entry](#quick-entry-global-hotkey-on-gnome-wayland) below); everything
else is a faithful repackage.

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

These packages carry two small GNOME-Wayland patches applied to `app.asar` at
build time (see below). The app is otherwise unmodified.

## Quick Entry global hotkey on GNOME Wayland

The official build's global Quick Entry hotkey does not work on GNOME Wayland: it
goes through Chromium's GlobalShortcuts portal, which is broken for non-sandboxed
apps on `xdg-desktop-portal` 1.20+ (see
[electron/electron#51875](https://github.com/electron/electron/issues/51875)).

These packages fix it: a patch exposes the app's own Quick Entry toggle over a
Unix socket, and the `claude-desktop` launcher gains a `--toggle` command. Bind
it to a native GNOME shortcut:

```bash
claude-desktop --install-gnome-hotkey     # binds Ctrl+Alt+Space -> claude-desktop --toggle
# custom key: CLAUDE_QE_ACCEL='<Super>space' claude-desktop --install-gnome-hotkey
# remove:     claude-desktop --uninstall-gnome-hotkey
```

The shortcut opens and closes Quick Entry in ~5-25 ms, bypassing the broken
portal entirely. A second patch gives the Quick Entry window its own WM_CLASS
(`claude-quick-entry`) so GNOME corner/shadow extensions can blacklist just that
window without affecting the main one.
