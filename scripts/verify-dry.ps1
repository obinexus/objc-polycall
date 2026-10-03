$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$adapterPath = Join-Path $root 'src/objc_polycall.c'
$objcPath = Join-Path $root 'src/OBNPolycall.m'
# No file, socket or parsing code of its own: every such call goes through the
# core. Patterns are anchored so core calls like polycall_peer_open( do not match.
$forbidden = '(^|[^A-Za-z0-9_])(fopen|open|CreateFile[AW]?|sscanf|strtok|socket|connect)\('
$matches = Select-String -Path $adapterPath,$objcPath -Pattern $forbidden

if ($matches) {
    $matches | ForEach-Object { Write-Error $_.Line }
    throw 'objc-polycall must not parse configuration or implement runtime logic'
}

$adapter = Get-Content -Raw $adapterPath
$objc = Get-Content -Raw $objcPath
if (-not $adapter.Contains('polycall_ffi_run_config(config_path, 1)')) {
    throw 'objc-polycall does not forward through polycall_ffi_run_config'
}
if (-not $adapter.Contains('#include <polycall.h>') -or -not $objc.Contains('#include <polycall.h>')) {
    throw 'objc-polycall must include the core header <polycall.h>'
}
if (-not $objc.Contains('[configPath UTF8String]')) {
    throw 'objc-polycall does not marshal NSString as UTF-8'
}
if (-not $objc.Contains('NSError errorWithDomain:OBNPolycallErrorDomain')) {
    throw 'objc-polycall does not expose Cocoa-style NSError handling'
}
if (Test-Path (Join-Path $root 'generated/polycall/polycall_ffi.h')) {
    throw "stub generated/polycall/polycall_ffi.h is back; use the core's <polycall.h>"
}

Write-Output 'objc-polycall thin-adapter check: PASS'
