#!/usr/bin/env bash
set -euo pipefail

# Reuse this script as temporary mocks; unit tests never download vendor files.
case ${0##*/} in
    curl)
        printf '%s\n' "$@" > "$TEST_CURL_ARGS"
        [[ ${TEST_DOWNLOAD_FAIL:-0} != 1 ]] || exit 22
        output=''
        while (( $# )); do
            case $1 in
                --output) output=$2; shift 2 ;;
                *) shift ;;
            esac
        done
        [[ -n $output ]]
        cp -- "$TEST_PACKAGE" "$output"
        exit 0
        ;;
    dnf)
        : > "$TEST_DNF_CALLED"
        exit 99
        ;;
    gtk-update-icon-cache)
        exit 0
        ;;
esac

project_dir=$(dirname -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")")
installer="$project_dir/install-epic-games-launcher.sh"
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/epic-installer-test.XXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT
mkdir -p "$temp_dir/bin" "$temp_dir/fixture/DEBIAN" "$temp_dir/download" \
    "$temp_dir/offline" "$temp_dir/failure" "$temp_dir/tmp"

printf '%s\n' 'Package: epic-games-launcher' 'Version: 1.0' 'Architecture: amd64' \
    'Maintainer: Installer Tests <nobody@example.invalid>' \
    'Description: Synthetic installer test package' > "$temp_dir/fixture/DEBIAN/control"
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
    install -D -m 0644 /dev/null "$temp_dir/fixture/$file"
done
dpkg-deb --build --root-owner-group "$temp_dir/fixture" "$temp_dir/fixture.deb" >/dev/null
for tool in curl dnf gtk-update-icon-cache; do
    install -m 0755 "${BASH_SOURCE[0]}" "$temp_dir/bin/$tool"
done
export PATH="$temp_dir/bin:$PATH" TMPDIR="$temp_dir/tmp"
export TEST_PACKAGE="$temp_dir/fixture.deb" TEST_CURL_ARGS="$temp_dir/curl.args"
export TEST_DNF_CALLED="$temp_dir/dnf.called"

expect_failure() {
    local expected=$1 output
    shift
    if output=$("$@" 2>&1); then
        printf 'FAIL: command unexpectedly succeeded: %s\n' "$*" >&2
        exit 1
    fi
    [[ $output == *"$expected"* ]] || {
        printf 'FAIL: expected %s, received %s\n' "$expected" "$output" >&2
        exit 1
    }
}

env DESTDIR="$temp_dir/download" "$installer" >/dev/null
grep -Fxq 'https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncher-x86_64.deb' "$TEST_CURL_ARGS"
grep -Fxq -- '--proto' "$TEST_CURL_ARGS"
grep -Fxq -- '--proto-redir' "$TEST_CURL_ARGS"
[[ $(grep -Fxc '=https' "$TEST_CURL_ARGS") == 2 ]]
[[ -x $temp_dir/download/opt/epic-games-launcher/run-epic-games-launcher.sh ]]
[[ -f $temp_dir/download/usr/local/share/icons/hicolor/256x256/apps/EpicGamesLauncher.png ]]
desktop-file-validate "$temp_dir/download/usr/local/share/applications/epic-games-launcher.desktop"
printf 'PASS: official HTTPS download, wrapper, desktop entry and normalized icons\n'

rm -- "$TEST_CURL_ARGS"
env DESTDIR="$temp_dir/offline" "$installer" "$TEST_PACKAGE" >/dev/null
[[ ! -e $TEST_CURL_ARGS ]]
printf 'PASS: explicit local package works without downloading\n'

expect_failure 'Destination already exists' env DESTDIR="$temp_dir/download" "$installer"
[[ ! -e $TEST_CURL_ARGS ]]
printf 'PASS: existing installation is rejected before network access\n'

expect_failure 'Download failed' env TEST_DOWNLOAD_FAIL=1 DESTDIR="$temp_dir/failure" "$installer"
[[ ! -e $temp_dir/failure/opt/epic-games-launcher ]]
expect_failure 'Not an epic-games-launcher' env DESTDIR="$temp_dir/failure" "$installer" "$installer"
expect_failure 'DESTDIR must' env DESTDIR=relative "$installer"
if (( EUID != 0 )); then
    expect_failure 'sudo' env -u DESTDIR "$installer"
fi
[[ ! -e $TEST_DNF_CALLED ]]
printf 'PASS: download/input failures are safe, and staging never invokes dnf\n'
