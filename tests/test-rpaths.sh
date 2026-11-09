#!/usr/bin/env bash
set -euo pipefail

temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/epic-rpath-test.XXXXXX")
trap 'rm -rf -- "$temp_dir"' EXIT
rpm_config_dir=$(rpm --eval '%{_rpmconfigdir}')
sed 's/ORIGINX/ORIGIN/g' "$rpm_config_dir/check-rpaths-worker" > "$temp_dir/checker"

# Empty shared objects exercise validation without running any test binaries.
as --64 -o "$temp_dir/probe.o" /dev/null
ld --shared --enable-new-dtags -rpath '${ORIGIN}:${ORIGIN}/..' \
    -o "$temp_dir/valid.so" "$temp_dir/probe.o"
readelf --dynamic "$temp_dir/valid.so" | grep -Fq '(RUNPATH)'
env QA_RPATHS=0 RPM_BUILD_ROOT="$temp_dir" \
    bash "$temp_dir/checker" "$temp_dir/valid.so"
printf 'PASS: valid braced ORIGIN paths are accepted\n'

for rpath in 'relative/path' './relative/path' '${ORIGINX}'; do
    ld --shared --enable-new-dtags -rpath "$rpath" -o "$temp_dir/invalid.so" "$temp_dir/probe.o"
    readelf --dynamic "$temp_dir/invalid.so" | grep -Fq '(RUNPATH)'
    if env QA_RPATHS=0 RPM_BUILD_ROOT="$temp_dir" \
        bash "$temp_dir/checker" "$temp_dir/invalid.so" >/dev/null 2>&1; then
        printf 'FAIL: unsafe or undefined RPATH was accepted: %s\n' "$rpath" >&2
        exit 1
    fi
done
printf 'PASS: invalid, relative and undefined ORIGINX paths remain rejected\n'
