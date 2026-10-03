#!/bin/sh
# objc-polycall test matrix against the REAL installed Polycall core.
#
# Prerequisites: an Objective-C compiler with Foundation (GNUstep: gobjc +
# gnustep-config; macOS: clang), GNU make, and the core installed so that
#   pkg-config --cflags --libs polycall   works (set PKG_CONFIG_PATH),
#   libpolycall is resolvable             (LD_LIBRARY_PATH or ldconfig),
#   the `polycall` CLI is on PATH         (daemon + C peer interop checks).
# In the QA image: sh /qa/build-linux-core.sh, then
#   PATH=/opt/polycall/bin:$PATH LD_LIBRARY_PATH=/opt/polycall/lib \
#   PKG_CONFIG_PATH=/opt/polycall/lib/pkgconfig sh tests/run-real-core.sh
#
# A missing prerequisite is reported as SKIP with exit status 77, never as
# success; optional tools (valgrind, npm) print SKIP for their step.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT" || exit 1

skip() { echo "SKIP: $1"; exit 77; }
command -v make >/dev/null 2>&1 || skip "make not found"
pkg-config --exists polycall 2>/dev/null || skip "pkg-config cannot find polycall (install the core, set PKG_CONFIG_PATH)"
command -v polycall >/dev/null 2>&1 || skip "polycall CLI not on PATH (needed for daemon and C-peer interop checks)"
if [ "$(uname -s)" != Darwin ] && ! command -v gnustep-config >/dev/null 2>&1; then
  skip "gnustep-config not found (install gnustep-devel / gobjc)"
fi

echo "== compiler: $(${CC:-cc} --version 2>&1 | head -1)"
command -v gnustep-config >/dev/null 2>&1 && echo "== GNUstep: $(gnustep-config --variable=GNUSTEP_MAKEFILES 2>/dev/null) base $(pkg-config --modversion gnustep-base 2>/dev/null || dpkg-query -W -f='${Version}' libgnustep-base-dev 2>/dev/null)"
echo "== core: $(polycall --version) via pkg-config $(pkg-config --modversion polycall)"
POLYCALL_LIBDIR=${POLYCALL_LIBDIR:-$(pkg-config --variable=libdir polycall)}
export POLYCALL_LIBDIR
FAIL=0
run() { echo "== $*"; "$@" || { echo "FAILED: $*"; FAIL=1; }; }

run make clean
run make test            # adapter unit test (mock core)
run make verify-dry
run make test-real       # C shim, Objective-C suite, loader errors -- real core
if command -v valgrind >/dev/null 2>&1; then
  run sh tests/valgrind.sh build/objc_polycall_test
else
  echo "SKIP: valgrind not installed (memory check not run)"
fi
if command -v npm >/dev/null 2>&1; then
  run sh tests/npm-pack.sh
else
  echo "SKIP: npm not installed (package check not run)"
fi

[ "$FAIL" -eq 0 ] && echo "== objc-polycall real-core matrix: PASS" || echo "== objc-polycall real-core matrix: FAIL"
exit "$FAIL"
