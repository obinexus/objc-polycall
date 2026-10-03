#!/usr/bin/env sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# No file, socket or parsing code of its own: every such call goes through the
# core. Patterns are anchored so core calls like polycall_peer_open( do not match.
if grep -E -n '(^|[^A-Za-z0-9_])(fopen|open|CreateFile[AW]?|sscanf|strtok|socket|connect)\(' \
    "$root/src/objc_polycall.c" "$root/src/OBNPolycall.m"; then
    echo "objc-polycall must not parse configuration or implement runtime logic" >&2
    exit 1
fi

grep -F -q 'polycall_ffi_run_config(config_path, 1)' \
    "$root/src/objc_polycall.c"
grep -F -q '#include <polycall.h>' "$root/src/objc_polycall.c"
grep -F -q '#include <polycall.h>' "$root/src/OBNPolycall.m"
grep -F -q '[configPath UTF8String]' "$root/src/OBNPolycall.m"
grep -F -q 'NSError errorWithDomain:OBNPolycallErrorDomain' \
    "$root/src/OBNPolycall.m"
if [ -e "$root/generated/polycall/polycall_ffi.h" ]; then
    echo "stub generated/polycall/polycall_ffi.h is back; use the core's <polycall.h>" >&2
    exit 1
fi

echo "objc-polycall thin-adapter check: PASS"
