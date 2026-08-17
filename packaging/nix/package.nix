# Claude Desktop, packaged from this repo's release tarball (which already has all
# our patches baked in at release-build time). The bundled Electron 42 runtime +
# native modules are autoPatchelf'd for NixOS, so the app runs against the exact
# Electron it ships with and native modules (node-pty, claude-native, virtiofsd)
# keep working.
#
# Release-coupled: version + pkgrel + per-arch tarball sha256 are pinned below and
# bumped by a PR the release workflow opens on every release (scripts/bump-nix-pin.sh).
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
, makeWrapper
, alsa-lib
, at-spi2-atk
, at-spi2-core
, atk
, cairo
, cups
, dbus
, expat
, gdk-pixbuf
, glib
, gtk3
, libGL
, libdrm
, libgbm
, libnotify
, libpulseaudio
, libuuid
, libxkbcommon
, mesa
, nspr
, nss
, pango
, systemd
, libseccomp
, libcap_ng
, vulkan-loader
, xorg
, socat ? null
, qemu ? null      # opt-in: heavy; only for Cowork (`.override { qemu = pkgs.qemu; }`)
}:

let
  version = "1.30096.1";
  pkgrel = "0";
  tarballs = {
    x86_64-linux = {
      suffix = "linux";
      sha256 = "b1f772193cb22be8a5fd81e721adfe84e40bce6202c2b64af3eb07cf8d4e0625";
    };
    aarch64-linux = {
      suffix = "linux-aarch64";
      sha256 = "710a32b170f2576672e948884c9704370a882777464d898b214e51b4c0742788";
    };
  };
  t = tarballs.${stdenv.hostPlatform.system}
    or (throw "claude-desktop-repack: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-desktop-repack";
  inherit version;

  src = fetchurl {
    url = "https://github.com/boommasterxd/claude-desktop-repack/releases/download/v${version}-${pkgrel}/claude-desktop-repack-${version}-${pkgrel}-${t.suffix}.tar.gz";
    sha256 = t.sha256;
  };
  # Unpacks to claude-desktop-repack-<version>-<pkgrel>-<suffix>/ (default unpackPhase).

  nativeBuildInputs = [ autoPatchelfHook wrapGAppsHook3 makeWrapper ];

  buildInputs = [
    alsa-lib at-spi2-atk at-spi2-core atk cairo cups dbus expat
    gdk-pixbuf glib gtk3 libGL libdrm libgbm libnotify libpulseaudio
    libuuid libxkbcommon mesa nspr nss pango systemd
    libseccomp libcap_ng
    stdenv.cc.cc.lib
  ] ++ (with xorg; [
    libX11 libXcomposite libXcursor libXdamage libXext libXfixes libXi
    libXrandr libXrender libXScrnSaver libXtst libxcb libxshmfence
  ]);

  # dlopen'd at runtime, so autoPatchelf can't see them; append to RUNPATH.
  runtimeDependencies = [ libGL vulkan-loader libpulseaudio ];

  dontConfigure = true;
  dontBuild = true;
  dontWrapGApps = true; # we run makeWrapper ourselves, below

  installPhase = ''
    runHook preInstall

    # The tarball's usr/ tree is already patched (all repo patches applied at
    # release-build time). Install it verbatim.
    mkdir -p $out/lib/claude-desktop
    cp -a usr/lib/claude-desktop/. $out/lib/claude-desktop/

    [ -d usr/share/icons ] && cp -a usr/share/icons $out/share/
    install -Dm644 usr/share/applications/claude-desktop.desktop \
      $out/share/applications/claude-desktop.desktop

    # Quick Entry hotkey helper (bash; pokes the app's Unix socket).
    install -Dm755 usr/bin/claude-desktop-hotkey $out/bin/claude-desktop-hotkey
    patchShebangs $out/bin/claude-desktop-hotkey

    # The bundled Electron binary auto-loads resources/app.asar. Store binaries
    # can't be setuid, so run Chromium's sandbox off (like the AppImage/tarball).
    #
    # --run also honors opt-in env vars for the Electron/Ozone/Wayland
    # GPU-process crash workaround (issue #66): CLAUDE_GPU_BACKEND=angle-gl,
    # CLAUDE_USE_XWAYLAND=1, CLAUDE_DISABLE_GPU=full. See
    # packaging/launcher/claude-desktop-launcher for the equivalent used by
    # rpm/deb/Arch.
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "--no-sandbox" \
      --set ELECTRON_OZONE_PLATFORM_HINT auto \
      --run '
        case "''${CLAUDE_GPU_BACKEND:-}" in
          angle-gl) set -- --use-gl=angle --use-angle=gl "$@" ;;
        esac
        [ "''${CLAUDE_USE_XWAYLAND:-}" = "1" ] && set -- --ozone-platform=x11 "$@"
        [ "''${CLAUDE_DISABLE_GPU:-}" = "full" ] && set -- --disable-gpu "$@"
      ' \
      --prefix PATH : ${lib.makeBinPath (lib.optional (socat != null) socat
        ++ lib.optional (qemu != null) qemu)}

    runHook postInstall
  '';

  meta = {
    description = "Claude Desktop for Linux, repackaged from Anthropic's official Linux build";
    homepage = "https://github.com/boommasterxd/claude-desktop-repack";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "claude-desktop";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
