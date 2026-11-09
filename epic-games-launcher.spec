# Local vendor-binary repackaging, not an upstream source release.
# No main-application license was supplied. Public COPR publication is blocked
# until upload rights AND a Fedora-acceptable license are established.
# https://docs.copr.fedorainfracloud.org/user_documentation.html#what-i-can-build-in-copr

%global vendor_sha256 884def8de247bc279bea571be6f5dec6c5481ac94cc06af62b577624be56c201

# Preserve vendor binaries, including embedded assets and debug information.
%global debug_package %{nil}
%global _build_id_links none
%global __strip /bin/true

# Some rpm-build versions mistakenly recognize ${ORIGINX}, not ${ORIGIN}.
# Fix only that spelling in a private checker; keep all RPATH checks enabled.
%global __brp_check_rpaths find "$RPM_BUILD_ROOT" -type f -print0 | xargs -0 -r /bin/bash ./check-rpaths-worker

# The bundled EOS SDK is private, not a provider for other RPM packages.
%global __provides_exclude ^libEOSSDK-Linux-Shipping[.]so.*$
%global __requires_exclude ^libEOSSDK-Linux-Shipping[.]so.*$

Name:           epic-games-launcher
Version:        0.113.0+g2164614
Release:        1%{?dist}
Summary:        Epic Games Launcher with Fedora desktop integration
License:        LicenseRef-Unknown
URL:            https://store.epicgames.com/
Source0:        EpicGamesLauncher-x86_64-55a54575ea6d43568a9c78fdf2128567.deb
Source1:        epic-games-launcher.desktop
Source2:        run-epic-games-launcher.sh
ExclusiveArch:  x86_64

BuildRequires:  dpkg
BuildRequires:  desktop-file-utils
Requires:       webkit2gtk4.1%{?_isa}
Requires:       gtk3%{?_isa}
Requires:       libayatana-appindicator-gtk3%{?_isa}
Requires:       hicolor-icon-theme
Recommends:     xorg-x11-server-Xwayland
Conflicts:      eglv2
Conflicts:      eg-lv2

%description
Epic Games Launcher repackaged for Fedora from the vendor's Debian binary.
Includes standard application icons and desktop integration, and defaults to
X11/XWayland when available so the launcher's toast windows can be positioned.
The application itself is not rebuilt or modified.

%prep
%setup -q -c -T
printf '%%s  %%s\n' '%{vendor_sha256}' '%{SOURCE0}' | sha256sum --check -
test "$(dpkg-deb --field '%{SOURCE0}' Package)" = '%{name}'
test "$(dpkg-deb --field '%{SOURCE0}' Version)" = '%{version}'
test "$(dpkg-deb --field '%{SOURCE0}' Architecture)" = amd64
dpkg-deb --extract '%{SOURCE0}' payload
sed 's/ORIGINX/ORIGIN/g' '%{_rpmconfigdir}/check-rpaths-worker' > check-rpaths-worker

%build
# Prebuilt vendor application; no compilation or network access is needed.

%install
install -D -m 0755 '%{SOURCE2}' \
    '%{buildroot}%{_libdir}/%{name}/run-epic-games-launcher.sh'
install -D -m 0755 payload/usr/bin/EpicGamesLauncher \
    '%{buildroot}%{_libdir}/%{name}/app/usr/bin/EpicGamesLauncher'
install -D -m 0644 payload/usr/lib/epic-games-launcher/libEOSSDK-Linux-Shipping.so \
    '%{buildroot}%{_libdir}/%{name}/app/usr/lib/epic-games-launcher/libEOSSDK-Linux-Shipping.so'
install -D -m 0644 payload/usr/lib/epic-games-launcher/resources/ThirdPartyNotices.txt \
    '%{buildroot}%{_libdir}/%{name}/app/usr/lib/epic-games-launcher/resources/ThirdPartyNotices.txt'

install -d '%{buildroot}%{_bindir}'
ln -s '../%{_lib}/%{name}/run-epic-games-launcher.sh' \
    '%{buildroot}%{_bindir}/EpicGamesLauncher'
desktop-file-install --dir='%{buildroot}%{_datadir}/applications' '%{SOURCE1}'

for size in 32x32 128x128 256x256; do
    source_size=$size
    if [ "$size" = 256x256 ]; then
        source_size=256x256@2
    fi
    install -D -m 0644 "payload/usr/share/icons/hicolor/$source_size/apps/EpicGamesLauncher.png" \
        "%{buildroot}%{_datadir}/icons/hicolor/$size/apps/EpicGamesLauncher.png"
done

%check
sh -n '%{buildroot}%{_libdir}/%{name}/run-epic-games-launcher.sh'
desktop-file-validate '%{buildroot}%{_datadir}/applications/%{name}.desktop'
cmp payload/usr/bin/EpicGamesLauncher \
    '%{buildroot}%{_libdir}/%{name}/app/usr/bin/EpicGamesLauncher'
cmp payload/usr/lib/epic-games-launcher/libEOSSDK-Linux-Shipping.so \
    '%{buildroot}%{_libdir}/%{name}/app/usr/lib/epic-games-launcher/libEOSSDK-Linux-Shipping.so'
test "$(readlink '%{buildroot}%{_bindir}/EpicGamesLauncher')" = \
    '../%{_lib}/%{name}/run-epic-games-launcher.sh'

%files
%license payload/usr/lib/epic-games-launcher/resources/ThirdPartyNotices.txt
%{_bindir}/EpicGamesLauncher
%{_libdir}/%{name}/
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/32x32/apps/EpicGamesLauncher.png
%{_datadir}/icons/hicolor/128x128/apps/EpicGamesLauncher.png
%{_datadir}/icons/hicolor/256x256/apps/EpicGamesLauncher.png

%changelog
* Mon Nov 09 2026 Local Packaging - 0.113.0+g2164614-1
- Repackage vendor binaries with desktop icons and XWayland toast support.
