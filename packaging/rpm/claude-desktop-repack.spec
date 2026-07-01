# Repackaged from Anthropic's official Linux .deb. Prebuilt binaries:
# no strip, no debuginfo, no Provides leakage from the bundled private .so files.
# Pass at build time:  --define "_claude_version X"  --define "_claude_payload /path/to/payload"
%global __os_install_post %{nil}
%global debug_package %{nil}
%global __strip /bin/true
%global _build_id_links none
%global __provides_exclude_from ^/usr/lib/claude-desktop/.*$
%global __requires_exclude_from ^/usr/lib/claude-desktop/.*$

Name:           claude-desktop-repack
Version:        %{_claude_version}
Release:        1%{?dist}
Summary:        Desktop application for Claude.ai
License:        Proprietary
URL:            https://claude.ai
ExclusiveArch:  x86_64 aarch64

# Repackaged, not built from source: declare Fedora/RHEL runtime deps explicitly
# (translated from the upstream .deb control file) and disable ELF auto-scan.
AutoReqProv:    no

Requires:       glibc
Requires:       gtk3
Requires:       nss
Requires:       libnotify
Requires:       at-spi2-atk
Requires:       libdrm
Requires:       mesa-libgbm
Requires:       libxcb
Requires:       libsecret
Requires:       libXtst
Requires:       libuuid
Requires:       xdg-utils
Requires:       xdg-desktop-portal

Recommends:     alsa-lib
Recommends:     libappindicator-gtk3
Recommends:     (gnome-keyring or kwalletd5 or kwalletd6)
Recommends:     qemu-system-x86

# dnf installs/shows this as "claude-desktop-repack", but it ships the same app
# identity and file paths as a plain "claude-desktop": provide that name and
# conflict with any other package owning the same files.
Provides:       claude-desktop = %{version}-%{release}
Conflicts:      claude-desktop
Conflicts:      claude-desktop-bin

%description
Claude Desktop gives you Chat, Cowork, and Claude Code in a native desktop
app: parallel sessions, visual diff review, an integrated terminal and
editor, and live app preview.

This RPM is repackaged unmodified from Anthropic's official Linux .deb for
distributions the official apt repository does not target (Fedora, RHEL,
openSUSE). It is not affiliated with or endorsed by Anthropic.

%prep
# nothing to prep; payload is staged directly in %%install

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a %{_claude_payload}/. %{buildroot}/
# Keep the sandbox helper setuid regardless of umask.
chmod 4755 %{buildroot}/usr/lib/claude-desktop/chrome-sandbox
# Drop Debian-only cruft that has no meaning on RPM systems.
rm -rf %{buildroot}/usr/share/lintian

%post
update-desktop-database -q %{_datadir}/applications &>/dev/null || :
touch --no-create %{_datadir}/icons/hicolor &>/dev/null || :
gtk-update-icon-cache -q %{_datadir}/icons/hicolor &>/dev/null || :

%postun
if [ $1 -eq 0 ] ; then
    update-desktop-database -q %{_datadir}/applications &>/dev/null || :
    gtk-update-icon-cache -q %{_datadir}/icons/hicolor &>/dev/null || :
fi

%files
%{_bindir}/claude-desktop
%{_bindir}/claude-desktop-hotkey
/usr/lib/claude-desktop/
%{_datadir}/applications/claude-desktop.desktop
%{_datadir}/icons/hicolor/*/apps/claude-desktop.png
%doc %{_datadir}/doc/claude-desktop/copyright

%changelog
* Tue Jun 30 2026 claude-desktop-repack - repackaged
- Repackage of the official Claude Desktop .deb as an RPM.
