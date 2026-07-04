$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$adapterPath = Join-Path $root 'src/objc_polycall.c'
$objcPath = Join-Path $root 'src/OBNPolycall.m'
$forbidden = 'fopen|open\(|CreateFile|sscanf|strtok|socket\(|connect\('
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
if (-not $objc.Contains('[configPath UTF8String]')) {
    throw 'objc-polycall does not marshal NSString as UTF-8'
}
if (-not $objc.Contains('NSError errorWithDomain:OBNPolycallErrorDomain')) {
    throw 'objc-polycall does not expose Cocoa-style NSError handling'
}

Write-Output 'objc-polycall thin-adapter check: PASS'
