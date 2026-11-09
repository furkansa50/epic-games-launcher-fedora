#!/usr/bin/env bash
set -euo pipefail

if [[ ${1:-} == --probe ]]; then
    shift
    printf '%s\n' "${GDK_BACKEND-<unset>}" "$@"
    exit 0
fi

project_dir=$(dirname -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")")
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/epic-launcher-test.XXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT

install -D -m 0755 "$project_dir/run-epic-games-launcher.sh" "$temp_dir/path with spaces/run.sh"
install -D -m 0755 "${BASH_SOURCE[0]}" "$temp_dir/path with spaces/app/usr/bin/EpicGamesLauncher"
ln -s "$temp_dir/path with spaces/run.sh" "$temp_dir/launcher link"
launcher="$temp_dir/launcher link"

actual=$(env -u GDK_BACKEND DISPLAY=:99 WAYLAND_DISPLAY=wayland-test \
    "$launcher" --probe 'argument with spaces' 'com.epicgames.launcher://store?one=1&two=2')
[[ $actual == $'x11\nargument with spaces\ncom.epicgames.launcher://store?one=1&two=2' ]]
printf 'PASS: XWayland default, symlinks, spaces and URL arguments\n'

actual=$(env DISPLAY=:99 GDK_BACKEND=wayland "$launcher" --probe)
[[ $actual == wayland ]]
printf 'PASS: explicit native-Wayland override is preserved\n'

actual=$(env DISPLAY=:99 GDK_BACKEND= "$launcher" --probe)
[[ -z $actual ]]
printf 'PASS: an explicitly empty backend is preserved\n'

actual=$(env -u DISPLAY -u GDK_BACKEND WAYLAND_DISPLAY=wayland-test "$launcher" --probe)
[[ $actual == '<unset>' ]]
printf 'PASS: no forced X11 when XWayland is unavailable\n'

actual=$(env -u WAYLAND_DISPLAY -u GDK_BACKEND DISPLAY=:99 "$launcher" --probe)
[[ $actual == x11 ]]
printf 'PASS: native X11 sessions are supported\n'
