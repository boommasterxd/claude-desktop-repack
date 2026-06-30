# claude-desktop-repack

Automatically repackages Anthropic's **official** Claude Desktop Linux build
(shipped only as a `.deb` for Debian/Ubuntu) into other package formats for
distributions the official apt repository does not target, starting with **RPM**
(Fedora, RHEL, openSUSE).

The packages are produced **unmodified** from the official `.deb`. No patching,
no re-signing of the application: this is pure re-packaging. A scheduled GitHub
Action watches Anthropic's apt repository and, whenever a new version appears,
rebuilds the packages and publishes a GitHub Release.

> Not affiliated with or endorsed by Anthropic. The Claude Desktop application
> is Anthropic's; this project only re-wraps the official Linux binary so it can
> be installed on more distributions. Source of truth is always
> <https://claude.com/download>.

## Install (Fedora / RHEL / openSUSE)

Download the latest `.rpm` for your architecture from the
[Releases](../../releases) page, then:

```bash
sudo dnf install ./claude-desktop-*.x86_64.rpm
```

Launch **Claude** from your app launcher, or run `claude-desktop` from a terminal.

If you previously installed the patched `claude-desktop-bin`, this package
conflicts with it (same paths); swap in one transaction:

```bash
sudo dnf swap claude-desktop-bin ./claude-desktop-*.rpm
```

## How it works

| Step | What happens |
|------|--------------|
| Detect | `scripts/detect-version.sh` reads the apt `Packages` index and picks the highest version (`Version`, `Filename`, `SHA256`). |
| Fetch | `scripts/fetch-deb.sh` downloads the `.deb`, verifies its SHA256 against the index, extracts the payload, and asserts the expected layout. |
| Build | `scripts/build-rpm.sh` feeds the payload into `packaging/rpm/claude-desktop.spec`: Debian deps are translated to Fedora names, `chrome-sandbox` keeps its setuid bit, Debian-only apt/AppArmor maintainer scripts are dropped. |
| Release | `.github/workflows/release.yml` runs the above on a cron, and on a new version publishes a Release and records it in `.upstream-version`. |

### Local test builds

The CI calls the same per-format scripts you can run by hand. The convenience
wrapper builds everything into `./dist`:

```bash
scripts/build-local.sh                 # all formats, amd64 (x86_64)
scripts/build-local.sh amd64 rpm       # just the x86_64 RPM
scripts/build-local.sh arm64           # all formats, aarch64 (cross-built)
```

Or call a single format directly:

```bash
scripts/build-rpm.sh      amd64 dist
scripts/build-tarball.sh  amd64 dist
scripts/build-appimage.sh amd64 dist
```

`deb` is not in the default set (it needs `dpkg-deb`, which is absent on most
RPM distros); request it explicitly once `dpkg` is installed:

```bash
scripts/build-local.sh amd64 deb       # needs dpkg-deb (Fedora: dnf install dpkg)
```

Tooling: `rpmbuild` (`rpm-build`), `ar` (`binutils`), `tar`, `xz`, `curl`;
`appimagetool` is downloaded on demand; `dpkg-deb` (`dpkg`) only for the `.deb`.
Export `GPG_PRIVATE_KEY` to also sign the local build. Cross-arch builds only
package files (no compilation), so an aarch64 build runs fine on an x86_64 host
but cannot be smoke-tested there.

## Quick Entry global hotkey on GNOME Wayland

The official build's global Quick Entry hotkey **does not work on GNOME
Wayland**. The app registers it through Chromium's GlobalShortcuts portal path,
which fails because Chromium never performs the
`org.freedesktop.host.portal.Registry.Register` handshake that
`xdg-desktop-portal` 1.20+ requires for non-sandboxed apps
(see [electron/electron#51875](https://github.com/electron/electron/issues/51875)).
Symptom in `~/.config/Claude/logs/main.log`:

```
Global shortcut registration refused { accelerator: 'Alt+Ctrl+Space', identifier: 0 }
```

You can open Quick Entry from the tray icon ("Open Quick Entry"), and you can
get a real hotkey back with a small workaround that drives that same tray menu
item over D-Bus, then binds it to a native GNOME keyboard shortcut. This avoids
the broken portal entirely.

1. Install the helper script:

   ```bash
   install -Dm755 extras/claude-quick-entry ~/.local/bin/claude-quick-entry
   ```

2. Bind it to a key. Either via **Settings -> Keyboard -> Custom Shortcuts**
   (command: `~/.local/bin/claude-quick-entry`, shortcut: your choice), or from
   the terminal:

   ```bash
   BASE=/org/gnome/settings-daemon/plugins/media-keys
   KB="$BASE/custom-keybindings/claude-quick-entry/"
   # keep any existing custom shortcuts, then append ours:
   cur=$(dconf read $BASE/custom-keybindings)
   case "$cur" in
     *"$KB"*) : ;;
     ""|"@as []"|"[]") dconf write $BASE/custom-keybindings "['$KB']" ;;
     *) dconf write $BASE/custom-keybindings "${cur%]}, '$KB']" ;;
   esac
   dconf write "${KB}name"    "'Claude Quick Entry'"
   dconf write "${KB}command" "'$HOME/.local/bin/claude-quick-entry'"
   dconf write "${KB}binding" "'<Control><Alt>space'"
   ```

The script resolves Claude's tray item dynamically (its D-Bus name changes on
every start) and finds the Quick Entry menu entry by label, so it keeps working
across restarts. It requires the app's tray icon to be present (on GNOME, the
**AppIndicator and KStatusNotifierItem Support** extension).

## Status

- [x] RPM (x86_64, aarch64)
- [x] Generic tarball (x86_64, aarch64)
- [x] AppImage + .zsync (x86_64, aarch64; not sandboxed, so Claude Code / Cowork keep host access)
- [x] .deb (amd64, arm64; rebuilt from the official payload with upstream's control + maintainer scripts)
- [ ] Arch (AUR)

The `.deb` is included for convenience and parity, but on **Debian / Ubuntu**
you should prefer Anthropic's
[official apt repository](https://code.claude.com/docs/en/desktop-linux): only
that path delivers automatic updates through `apt upgrade`. The `.deb` here is a
functionally-equivalent rebuild of the official payload, not a separate build.

**Flatpak** is intentionally not a target: the sandbox cuts Claude Code and
Cowork off from the host toolchain (no `git` / `node` / compilers in PATH, no
`/dev/kvm`), which breaks the very features that make the desktop app useful.

## Signing and verification

This project is independent: it reuses no signing keys, AUR credentials, or
release infrastructure from any other Claude-on-Linux project. It uses **its
own** key. The release job signs:

- every **RPM** with an embedded GPG signature (native `dnf` / `rpm --checksig`),
- a detached **`SHA256SUMS.txt.asc`** that covers the AppImages and tarballs too,

and publishes the public key as `RELEASE-PUBKEY.asc` on each release. The chain
of trust starts at the official `.deb`: `fetch-deb.sh` verifies its SHA256
against Anthropic's signed apt index before anything is repackaged.

### One-time maintainer setup

```bash
# Generate a dedicated signing key (passphraseless is fine for CI: the GitHub
# secret is the protection). Use a real name/email you control.
gpg --batch --quick-generate-key "Your Name (claude-desktop-repack) <you@example.com>" rsa4096 sign never
gpg --armor --export-secret-keys YOUR_KEY_ID   # -> paste into the secret below
gpg --armor --export        YOUR_KEY_ID > RELEASE-PUBKEY.asc   # commit this
```

Add the private key under **Settings -> Secrets and variables -> Actions**:

- `GPG_PRIVATE_KEY` (required) - the ASCII-armored private key
- `GPG_PASSPHRASE` (optional) - only if the key has a passphrase

Without `GPG_PRIVATE_KEY` the build still works and ships an unsigned
`SHA256SUMS.txt`. The `.zsync` AppImage update transport always points at this
repository's own releases (via `${{ github.repository }}`), nothing external.

### Verifying a download

```bash
# RPM (native):
sudo rpm --import RELEASE-PUBKEY.asc
rpm --checksig claude-desktop-*.rpm

# AppImage / tarball (via the signed manifest):
gpg --import RELEASE-PUBKEY.asc
gpg --verify SHA256SUMS.txt.asc SHA256SUMS.txt
sha256sum -c SHA256SUMS.txt
```
