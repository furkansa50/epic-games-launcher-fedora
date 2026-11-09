#!/bin/sh
set -eu

launcher_dir=$(dirname -- "$(readlink -f -- "$0")")

# The vendor's toast windows use absolute positioning, unsupported on Wayland.
# Use X11/XWayland when available; GDK_BACKEND=wayland remains an explicit opt-out.
if [ "${GDK_BACKEND+x}" != x ] && [ -n "${DISPLAY:-}" ]; then
    export GDK_BACKEND=x11
fi

exec "$launcher_dir/app/usr/bin/EpicGamesLauncher" "$@"
