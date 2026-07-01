# claude-desktop-repack

Repackages Anthropic's official Claude Desktop Linux build into the formats it
is not shipped in, so distributions Anthropic does not target can install it too.

## Why

Anthropic ships Claude Desktop for Linux only as a `.deb` for Debian/Ubuntu (via
their apt repository). There is no native RPM, AppImage or tarball, so Fedora,
RHEL, openSUSE and others are left out.

This repo takes the **official `.deb`** and re-wraps it into:

- **RPM** (x86_64, aarch64) for Fedora / RHEL / openSUSE
- **Arch package** `.pkg.tar.zst` (x86_64, aarch64) for Arch / Manjaro / EndeavourOS
- **AppImage** + `.zsync` (x86_64, aarch64) for any glibc distro
- **tarball** (x86_64, aarch64), generic and portable
- **.deb** (amd64, arm64), rebuilt for parity (on Debian/Ubuntu prefer the
  [official apt repo](https://code.claude.com/docs/en/desktop-linux) for updates)
- **Nix flake** (x86_64, aarch64) for NixOS / the Nix package manager

A scheduled GitHub Action watches Anthropic's apt index and publishes a new
signed GitHub Release whenever upstream releases a new version. The only change
to the app is a few small patches (see [Patches](#patches) below); everything
else is a faithful repackage.

> Not affiliated with or endorsed by Anthropic. Source of truth:
> <https://claude.com/download>.

## Install

Easiest, with **automatic updates** (Fedora / RHEL / openSUSE):

```bash
sudo dnf config-manager --add-repo https://boommasterxd.github.io/claude-desktop-repack/rpm/claude-desktop-repack.repo
sudo dnf install claude-desktop-repack   # updates then come with `dnf upgrade`
```

The [install page](https://boommasterxd.github.io/claude-desktop-repack/) has the
commands for every distro. The repo hosts only the (signed) metadata; the packages
themselves are served from the release. (An Arch pacman repo and an apt repo are on
the way; until then use the release files below.)

Or grab the file for your distro and architecture directly from [Releases](../../releases):

```bash
# Fedora / RHEL / openSUSE
sudo dnf install ./claude-desktop-repack-*.x86_64.rpm

# Arch / Manjaro / EndeavourOS
sudo pacman -U ./claude-desktop-repack-*-x86_64.pkg.tar.zst
# (or build it yourself: download the release PKGBUILD + .install, then `makepkg -si`)

# Portable (any distro)
chmod +x claude-desktop-repack-*-x86_64.AppImage && ./claude-desktop-repack-*-x86_64.AppImage
```

On **Nix / NixOS** it is a flake (proprietary app, so allow unfree):

```bash
NIXPKGS_ALLOW_UNFREE=1 nix profile install --impure github:boommasterxd/claude-desktop-repack
# or add to a flake: inputs.claude-desktop-repack.url = "github:boommasterxd/claude-desktop-repack";
```

Optional verification (each release ships `RELEASE-PUBKEY.asc` + `SHA256SUMS.txt.asc`):

```bash
gpg --import RELEASE-PUBKEY.asc
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt && sha256sum -c SHA256SUMS.txt
```

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
distro. Cosmetic and fully guarded - any failure falls back to the original string.

## Maintaining

- **Add a patch:** drop a module into `patches/` that exports `name`, `apply(code)`
  and (optional) `description`. It is applied by the build, listed in the release
  notes, and validated automatically (a non-matching patch fails the build and
  files an issue). Nothing else to wire.
- **New upstream system paths:** the build scans the bundle for absolute system
  paths and fails if one appears that is not in `baseline/system-paths.json`. A
  new `/usr/share`, `/usr/lib`, `/usr/libexec` (etc.) path may be Debian-specific
  and break Fedora/RHEL/Arch (like the OVMF firmware paths). Review it, then
  allowlist benign ones (`node scripts/check-native-paths.mjs <payloadDir> --update`,
  review the diff) or write a patch for Debian-specific ones.
- **Ship a packaging fix** for the same upstream version (e.g. after fixing a
  patch): merge the fix, then run the workflow with **`force: true`**. It
  publishes the next revision `v<version>-<N>` (RPM `Release`, deb revision),
  which package managers see as an upgrade. A new upstream version starts at
  `-0` again. The revision is derived from the published releases, nothing to
  edit.
- Release notes are generated: the patch list from `patches/`, plus a changelog
  of your commits since the previous release, grouped by conventional-commit type.
