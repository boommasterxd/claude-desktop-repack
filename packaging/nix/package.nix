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
  version = "1.17377.1";
  pkgrel = "0";
  tarballs = {
    x86_64-linux = {
      suffix = "linux";
      sha256 = "3f75b570efd42f45f934b0251950a899f6507e03132f1571f9e4ffcbf02c11f6";
    };
    aarch64-linux = {
      suffix = "linux-aarch64";
      sha256 = "017b29a51a02541b34be328cfaf7089caaaf07989f99cc300038710f330f596b";
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
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "--no-sandbox" \
      --set ELECTRON_OZONE_PLATFORM_HINT auto \
      --prefix PATH : ${lib.makeBinPath (lib.optional (socat != null) socat
        ++ lib.optional (qemu != null) qemu)}

    runHook postInstall
  '';

  meta = {
    description = "Claude Desktop for Linux, repackaged from the official .deb";
    homepage = "https://github.com/boommasterxd/claude-desktop-repack";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "claude-desktop";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
