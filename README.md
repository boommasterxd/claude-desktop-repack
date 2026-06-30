# claude-desktop-repack

Repackages Anthropic's official Claude Desktop Linux build into the formats it
is not shipped in, so distributions Anthropic does not target can install it too.

## Why

Anthropic ships Claude Desktop for Linux only as a `.deb` for Debian/Ubuntu (via
their apt repository). There is no native RPM, AppImage or tarball, so Fedora,
RHEL, openSUSE and others are left out.

This repo takes the **official `.deb`, unchanged**, and re-wraps it into:

- **RPM** (x86_64, aarch64) for Fedora / RHEL / openSUSE
- **AppImage** + `.zsync` (x86_64, aarch64) for any glibc distro
- **tarball** (x86_64, aarch64), generic and portable
- **.deb** (amd64, arm64), rebuilt for parity (on Debian/Ubuntu prefer the
  [official apt repo](https://code.claude.com/docs/en/desktop-linux) for updates)

A scheduled GitHub Action watches Anthropic's apt index and publishes a new
signed GitHub Release whenever upstream releases a new version. No patching, pure
repackaging.

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

## Quick Entry global hotkey on GNOME Wayland

The official build's global Quick Entry hotkey does not work on GNOME Wayland: it
goes through Chromium's GlobalShortcuts portal, which is broken for non-sandboxed
apps on `xdg-desktop-portal` 1.20+ (see
[electron/electron#51875](https://github.com/electron/electron/issues/51875)).

You can still open Quick Entry from the tray icon. To get a real hotkey, trigger
that same tray menu item over D-Bus and bind it to a **native** GNOME shortcut,
which bypasses the broken portal:

1. Get the helper. The RPM, `.deb` and tarball already install it as
   `claude-quick-entry` (in your `PATH`). For the AppImage, download the
   standalone `claude-quick-entry` from the same release and drop it on your
   `PATH`, e.g. `install -Dm755 claude-quick-entry ~/.local/bin/claude-quick-entry`.

2. Bind it to a key, either via **Settings -> Keyboard -> Custom Shortcuts**
   (command `claude-quick-entry`), or from a terminal:

   ```bash
   BASE=/org/gnome/settings-daemon/plugins/media-keys
   KB="$BASE/custom-keybindings/claude-quick-entry/"
   cur=$(dconf read $BASE/custom-keybindings)
   case "$cur" in
     *"$KB"*) : ;;
     ""|"@as []"|"[]") dconf write $BASE/custom-keybindings "['$KB']" ;;
     *) dconf write $BASE/custom-keybindings "${cur%]}, '$KB']" ;;
   esac
   dconf write "${KB}name"    "'Claude Quick Entry'"
   dconf write "${KB}command" "'claude-quick-entry'"
   dconf write "${KB}binding" "'<Control><Alt>space'"
   ```

The script finds Claude's tray item dynamically, so it survives restarts. It
needs the app's tray icon to be present (on GNOME: the **AppIndicator and
KStatusNotifierItem Support** extension).
