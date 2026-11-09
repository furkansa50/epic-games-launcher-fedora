#!/usr/bin/env bash
set -euo pipefail
umask 022
export LC_ALL=C

readonly download_url='https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncher-x86_64.deb'

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
    printf '%s\n' \
        'Unofficial Epic Games Launcher installer for dnf-based Fedora/Nobara (x86_64).' \
        'Usage: sudo ./install-epic-games-launcher.sh [path/to/package.deb]' \
        'Without a package argument, downloads the latest .deb directly from Epic over HTTPS.' \
        'Missing native dependencies are installed automatically with dnf.' \
        'Clone or download the entire repository before running this script.' \
        'Installs to /opt/epic-games-launcher and adds a command, desktop entry and icons.' \
        'Existing installations are never overwritten. Debian maintainer scripts are not run.' \
        'The application is never launched as root. No RPM/DPKG database entry is created.' \
        'Staging test: DESTDIR=/existing/empty/directory ./install-epic-games-launcher.sh [package.deb]' \
        'Staging mode needs the extraction tools already installed and never runs dnf.' \
        "Download URL: $download_url"
    exit 0
fi
(( $# <= 1 )) || fail 'Specify at most one .deb package. See --help.'

destdir=${DESTDIR:-/}
[[ $destdir == /* && -d $destdir ]] || fail 'DESTDIR must be an existing absolute directory.'
destdir=$(realpath -e -- "$destdir")
destdir=${destdir%/}
if [[ -z $destdir && $EUID -ne 0 ]]; then
    fail 'Run this script with sudo for a system-wide installation.'
fi
[[ $(uname -m) == x86_64 ]] || fail 'Only x86_64 systems are supported.'

script_dir=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")
[[ -f $script_dir/run-epic-games-launcher.sh && -f $script_dir/epic-games-launcher.desktop ]] || \
    fail 'The launch script and epic-games-launcher.desktop must be beside this script. Download the complete repository.'
if (( $# == 1 )); then
    package=$1
    [[ -f $package && -r $package ]] || fail "Cannot read package: $package"
    package=$(realpath -e -- "$package")
fi

app_dir="$destdir/opt/epic-games-launcher"
command_path="$destdir/usr/local/bin/EpicGamesLauncher"
desktop_dir="$destdir/usr/local/share/applications"
icon_dir="$destdir/usr/local/share/icons/hicolor"
for target in "$app_dir" "$command_path" "$destdir/usr/bin/EpicGamesLauncher" \
    "$desktop_dir/epic-games-launcher.desktop" \
    "$icon_dir/32x32/apps/EpicGamesLauncher.png" \
    "$icon_dir/128x128/apps/EpicGamesLauncher.png" \
    "$icon_dir/256x256/apps/EpicGamesLauncher.png"; do
    [[ ! -e $target && ! -L $target ]] || fail "Destination already exists; refusing to overwrite or shadow it: $target"
done

required_tools=(dpkg-deb desktop-file-install desktop-file-edit desktop-file-validate update-desktop-database)
if (( $# == 0 )); then
    required_tools+=(curl)
fi
if [[ -z $destdir ]]; then
    [[ -r /etc/os-release ]] || fail 'Cannot identify the operating system.'
    . /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in
        *' fedora '*|*' nobara '*) ;;
        *) fail 'System installation is supported on Fedora/Nobara only.' ;;
    esac
    command -v rpm >/dev/null && command -v dnf >/dev/null || fail 'Both rpm and dnf are required.'
    declare -A missing_packages=()
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null; then
            case $tool in
                curl) missing_packages[curl]=1 ;;
                dpkg-deb) missing_packages[dpkg]=1 ;;
                *) missing_packages[desktop-file-utils]=1 ;;
            esac
        fi
    done
    for dependency in webkit2gtk4.1.x86_64 gtk3.x86_64 libayatana-appindicator-gtk3.x86_64 \
        hicolor-icon-theme xorg-x11-server-Xwayland.x86_64; do
        rpm -q --quiet "$dependency" || missing_packages["$dependency"]=1
    done
    if (( ${#missing_packages[@]} )); then
        printf 'Installing missing Fedora/Nobara dependencies with dnf...\n'
        dnf install --assumeyes "${!missing_packages[@]}"
    fi
fi
for tool in "${required_tools[@]}"; do
    command -v "$tool" >/dev/null || fail "Missing tool: $tool. Install curl, dpkg and desktop-file-utils first."
done

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/epic-games-installer.XXXXXX")
pending_dir=''
trap 'rm -rf -- "$temp_dir"; if [[ -n $pending_dir ]]; then rm -rf -- "$pending_dir"; fi' EXIT

if (( $# == 0 )); then
    package="$temp_dir/EpicGamesLauncher-x86_64.deb"
    printf 'Downloading the latest installer directly from Epic Games over HTTPS...\n'
    curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' \
        --connect-timeout 20 --max-time 900 --retry 3 --retry-max-time 180 \
        --output "$package" "$download_url" || fail 'Download failed; no application files were installed.'
fi
[[ $(dpkg-deb --field "$package" Package) == epic-games-launcher ]] || fail 'Not an epic-games-launcher Debian package.'
[[ $(dpkg-deb --field "$package" Architecture) == amd64 ]] || fail 'The package must have amd64 architecture.'
version=$(dpkg-deb --field "$package" Version)
printf 'Preparing Epic Games Launcher %s...\n' "$version"

# Extract data only; never run Debian maintainer scripts or the app as root.
dpkg-deb --extract "$package" "$temp_dir/unpacked"
files=(
    usr/bin/EpicGamesLauncher
    usr/lib/epic-games-launcher/libEOSSDK-Linux-Shipping.so
    usr/lib/epic-games-launcher/resources/ThirdPartyNotices.txt
    usr/share/icons/hicolor/32x32/apps/EpicGamesLauncher.png
    usr/share/icons/hicolor/128x128/apps/EpicGamesLauncher.png
    usr/share/icons/hicolor/256x256@2/apps/EpicGamesLauncher.png
    usr/share/applications/epic-games-launcher.desktop
)
for file in "${files[@]}"; do
    source_path="$temp_dir/unpacked/$file"
    [[ -f $source_path && ! -L $source_path ]] || fail "Required regular file missing from package: $file"
    [[ $(realpath -e -- "$source_path") == "$temp_dir/unpacked/"* ]] || fail "Package path escapes extraction directory: $file"
done

desktop_edits=(
    --set-key=Exec '--set-value=/usr/local/bin/EpicGamesLauncher %u'
    --set-key=TryExec --set-value=/usr/local/bin/EpicGamesLauncher
    --set-icon=EpicGamesLauncher
)
desktop-file-install --dir="$temp_dir/menu" "${desktop_edits[@]}" \
    "$script_dir/epic-games-launcher.desktop"
desktop-file-validate "$temp_dir/menu/epic-games-launcher.desktop"

# Keep the original usr/bin -> usr/lib layout for the binary's $ORIGIN RUNPATH.
install -d -m 0755 "$destdir/opt" "$destdir/usr/local/bin" "$desktop_dir"
pending_dir=$(mktemp -d "$destdir/opt/.epic-games-launcher.XXXXXX")
for file in "${files[@]}"; do
    mode=0644
    [[ $file != usr/bin/EpicGamesLauncher ]] || mode=0755
    install -D -m "$mode" "$temp_dir/unpacked/$file" "$pending_dir/app/$file"
done
install -m 0755 "$script_dir/run-epic-games-launcher.sh" "$pending_dir/run-epic-games-launcher.sh"
chmod 0755 "$pending_dir"
mv -T -- "$pending_dir" "$app_dir"
pending_dir=''
ln -s /opt/epic-games-launcher/run-epic-games-launcher.sh "$command_path"
install -m 0644 "$temp_dir/menu/epic-games-launcher.desktop" "$desktop_dir/epic-games-launcher.desktop"
for size in 32x32 128x128 256x256; do
    source_size=$size
    [[ $size != 256x256 ]] || source_size=256x256@2
    install -D -m 0644 "$app_dir/app/usr/share/icons/hicolor/$source_size/apps/EpicGamesLauncher.png" \
        "$icon_dir/$size/apps/EpicGamesLauncher.png"
done
update-desktop-database "$desktop_dir"
if command -v gtk-update-icon-cache >/dev/null; then
    gtk-update-icon-cache --force --ignore-theme-index "$icon_dir"
fi

# A user-local shortcut shadows the system entry. Preserve its KDE/GPU settings.
if [[ -z $destdir && -n ${SUDO_USER:-} && ${SUDO_USER:-} != root ]]; then
    user_home=$(getent passwd "$SUDO_USER" | cut -d: -f6) || user_home=''
    user_desktop="$user_home/.local/share/applications/epic-games-launcher.desktop"
    if [[ -n $user_home && -f $user_desktop && ! -L $user_desktop ]] && {
        grep -Fxq -- "Exec=$script_dir/run-epic-games-launcher.sh %u" "$user_desktop" ||
        grep -Fxq -- "Exec=\"$script_dir/run-epic-games-launcher.sh\" %u" "$user_desktop"
    }; then
        if runuser -u "$SUDO_USER" -- desktop-file-edit "${desktop_edits[@]}" "$user_desktop"; then
            runuser -u "$SUDO_USER" -- update-desktop-database "$user_home/.local/share/applications" || \
                printf 'Warning: could not refresh the user desktop cache.\n' >&2
        else
            printf 'Warning: could not update the existing user shortcut: %s\n' "$user_desktop" >&2
        fi
    fi
fi

printf 'Installed Epic Games Launcher %s to %s\n' "$version" "$app_dir"
if [[ -n $destdir ]]; then
    printf 'Staging complete; the live system was not changed. Shortcuts use the final installation paths.\n'
else
    printf 'Launch from the application menu or run EpicGamesLauncher as your normal user.\n'
    printf 'This is a manual installation; no RPM/DPKG package database entry was created.\n'
fi
