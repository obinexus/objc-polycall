#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

if grep -E -n 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\(' \
    "$root/src/objc_polycall.c" "$root/src/OBNPolycall.m"; then
    echo "objc-polycall must not parse configuration or implement runtime logic" >&2
    exit 1
fi

grep -F -q 'polycall_ffi_run_config(config_path, 1)' \
    "$root/src/objc_polycall.c"
grep -F -q '[configPath UTF8String]' "$root/src/OBNPolycall.m"
grep -F -q 'NSError errorWithDomain:OBNPolycallErrorDomain' \
    "$root/src/OBNPolycall.m"

echo "objc-polycall thin-adapter check: PASS"
