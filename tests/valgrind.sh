#!/bin/sh
# Memory check: run the real-core Objective-C suite under valgrind memcheck.
#
# PASS when the suite passes under valgrind AND no valgrind error record
# (invalid access, uninitialised value, bad free, overlap, definite leak)
# has a frame in the binding (OBNPolycall.m, objc_polycall.c) or in
# libpolycall. Records without such a frame (GNUstep / glibc internals, e.g.
# NSTask, iconv_open's dynamic-loader strncmp) are listed and counted
# separately, not hidden.
#
# Usage: tests/valgrind.sh [test binary]   (default build/objc_polycall_test)
set -u
BIN=${1:-build/objc_polycall_test}
command -v valgrind >/dev/null 2>&1 || { echo "SKIP: valgrind not installed"; exit 77; }
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT
valgrind --leak-check=full --show-leak-kinds=definite --errors-for-leak-kinds=definite \
         --num-callers=40 --log-file="$LOG" "$BIN"
suite=$?
echo "== valgrind: $(grep -E 'ERROR SUMMARY' "$LOG" | sed 's/^==[0-9]*== //')"
grep -E 'definitely lost:|indirectly lost:' "$LOG" | sed 's/^==[0-9]*== /== /'
awk '
  /^==[0-9]+== (Invalid |Conditional jump|Use of uninitialised|Syscall param|Mismatched free|Source and destination overlap|.*are definitely lost)/ {
    inrec = 1; rec = $0; next }
  inrec && /^==[0-9]+== *$/ {
    inrec = 0; total++
    if (rec ~ /OBNPolycall\.m|objc_polycall\.c|libpolycall\.so/) { mine++; print "BINDING/CORE RECORD:\n" rec }
    else { split(rec, l, "\n"); sub(/^==[0-9]+== /, "", l[1])
           if (l[1] ~ /definitely lost/) l[1] = "definite leak record"; other[l[1]]++ }
    next }
  inrec { rec = rec "\n" $0 }
  END {
    for (k in other) printf "   other (no binding/libpolycall frame): %d x %s\n", other[k], k
    printf "== %d error records, %d involving the binding or libpolycall\n", total, mine + 0
    exit (mine + 0) > 0 }' "$LOG"
mine=$?
if [ "$suite" -eq 0 ] && [ "$mine" -eq 0 ]; then
  echo "== memory check: PASS"; exit 0
fi
echo "== memory check: FAIL (suite exit $suite)"; exit 1
