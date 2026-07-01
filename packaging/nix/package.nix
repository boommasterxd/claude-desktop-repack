# Claude Desktop, built from Anthropic's official Linux .deb, with the same
# patches this repo applies elsewhere. Self-contained: fetches the official .deb,
# applies the patches from ../../patches, and autoPatchelfs the bundled Electron
# 42 runtime + native modules for NixOS (no dependency on nixpkgs' electron, so
# the app runs against the exact Electron it was built for and its native .node
# modules keep working).
#
# Version + per-arch .deb sha256 are pinned below and bumped on each release.
{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, wrapGAppsHook3
, makeWrapper
, makeDesktopItem
, copyDesktopItems
, asar
, nodejs
, # Electron runtime closure
  alsa-lib
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
, # optional runtime tools
  socat ? null
, qemu ? null      # opt-in: heavy; only for Cowork (`.override { qemu = pkgs.qemu; }`)
}:

let
  version = "1.17377.1";
  debs = {
    x86_64-linux = {
      debArch = "amd64";
      sha256 = "f4bd78545200877b591179838de7ad7a577df6ed2e845969dd25690efc5c85c7";
    };
    aarch64-linux = {
      debArch = "arm64";
      sha256 = "658acbff14bd9c35d795ede46f097fca79d433ac4af792cdd6486acd3adc6f2e";
    };
  };
  d = debs.${stdenv.hostPlatform.system}
    or (throw "claude-desktop-repack: unsupported system ${stdenv.hostPlatform.system}");
in
stdenv.mkDerivation (finalAttrs: {
  pname = "claude-desktop-repack";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_${d.debArch}.deb";
    sha256 = d.sha256;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    wrapGAppsHook3
    makeWrapper
    copyDesktopItems
    asar
    nodejs
  ];

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

  # The .deb is an `ar` archive; extract its data payload.
  unpackPhase = ''
    runHook preUnpack
    ar x "$src"
    tar xf data.tar.*
    runHook postUnpack
  '';

  dontConfigure = true;

  # Patch the app.asar's index.js with our patch modules, then repack (keeping
  # native .node modules unpacked). The patch modules are dependency-free.
  buildPhase = ''
    runHook preBuild
    asar extract usr/lib/claude-desktop/resources/app.asar app-contents
    node ${./apply-patches.mjs} app-contents/.vite/build/index.js ${../../patches}
    node --check app-contents/.vite/build/index.js
    asar pack app-contents app.asar --unpack "*.node"
    runHook postBuild
  '';

  # We drive the wrapper ourselves, so let wrapGAppsHook only collect its args.
  dontWrapGApps = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/claude-desktop
    cp -r usr/lib/claude-desktop/. $out/lib/claude-desktop/

    # Swap in the patched app.asar (+ its unpacked native modules).
    cp app.asar $out/lib/claude-desktop/resources/app.asar
    rm -rf $out/lib/claude-desktop/resources/app.asar.unpacked
    if [ -d app.asar.unpacked ]; then
      cp -r app.asar.unpacked $out/lib/claude-desktop/resources/app.asar.unpacked
    fi

    # Icons.
    for sz in 16 32 48 128 256; do
      icon="usr/share/icons/hicolor/''${sz}x''${sz}/apps/claude-desktop.png"
      [ -f "$icon" ] && install -Dm644 "$icon" \
        "$out/share/icons/hicolor/''${sz}x''${sz}/apps/claude-desktop.png"
    done

    # Quick Entry hotkey helper (bash; pokes the app's Unix socket).
    install -Dm755 ${../launcher/claude-desktop-hotkey} $out/bin/claude-desktop-hotkey
    patchShebangs $out/bin/claude-desktop-hotkey

    # The bundled Electron binary auto-loads resources/app.asar. NixOS store
    # binaries can't be setuid, so run Chromium's sandbox off (like the AppImage
    # and tarball). Add optional runtime tools to PATH.
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "--no-sandbox" \
      --set ELECTRON_OZONE_PLATFORM_HINT auto \
      --prefix PATH : ${lib.makeBinPath ([ nodejs ]
        ++ lib.optional (socat != null) socat
        ++ lib.optional (qemu != null) qemu)}

    runHook postInstall
  '';

  desktopItems = [
    (makeDesktopItem {
      name = "claude-desktop";
      desktopName = "Claude";
      genericName = "AI Assistant";
      comment = "Desktop application for Claude.ai";
      keywords = [ "AI" "Chat" "Assistant" "Claude" "Code" "LLM" ];
      exec = "claude-desktop %U";
      icon = "claude-desktop";
      categories = [ "Utility" "Development" ];
      mimeTypes = [ "x-scheme-handler/claude" ];
      startupNotify = true;
      startupWMClass = "claude-desktop";
      terminal = false;
    })
  ];

  meta = {
    description = "Claude Desktop for Linux, repackaged from the official .deb";
    homepage = "https://github.com/boommasterxd/claude-desktop-repack";
    license = lib.licenses.unfree;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    mainProgram = "claude-desktop";
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
})
