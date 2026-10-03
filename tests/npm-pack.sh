#!/bin/sh
# Packaging check: `npm pack` this source package (never published), install
# the tarball into a clean temporary project, load its CommonJS entry point,
# and build + run the real-core targets from the INSTALLED copy.
set -u
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
command -v npm >/dev/null 2>&1 || { echo "SKIP: npm not installed"; exit 77; }
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

cd "$ROOT" || exit 1
echo "== npm pack (runs prepack: npm test)"
npm pack --pack-destination "$T" >"$T/pack.out" || { cat "$T/pack.out"; exit 1; }
TGZ=$(tail -1 "$T/pack.out")
echo "== packed $TGZ ($(wc -c <"$T/$TGZ") bytes)"
tar -tzf "$T/$TGZ" | sed 's/^/   /'

mkdir "$T/app" && cd "$T/app" || exit 1
npm init -y >/dev/null || exit 1
npm install --no-audit --no-fund "$T/$TGZ" || exit 1
node -e '
const assert = require("node:assert/strict");
const pkg = require("objc-polycall");
const meta = require("objc-polycall/package.json");
assert.equal(pkg.packageName, meta.name);
assert.ok(pkg.directories.src.relativeFiles.includes("OBNPolycall.m"));
assert.ok(pkg.directories.include.relativeFiles.includes("OBNPolycall.h"));
assert.equal(pkg.directories.generated, undefined, "the stub generated/ directory is gone");
assert.ok(require("node:fs").existsSync(pkg.makefile));
console.log("installed entry point OK:", meta.name, meta.version);
' || exit 1
cd "$T/app/node_modules/objc-polycall" || exit 1
echo "== make test-real in the installed package"
make test-real
