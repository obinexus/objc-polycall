# @obinexusltd/objc-polycall

Objective-C Foundation binding for
[libpolycall](https://github.com/obinexus/libpolycall) 1.5. The native adapter
maps Objective-C calls to the single core entry point:

```c
polycall_ffi_run_config(config_path, 1)
```

Configuration parsing, validation, networking, and runtime policy remain in
libpolycall. The Objective-C layer only converts `NSString` to UTF-8 and maps a
non-zero status into Cocoa's `NSError` convention.

## Install the source package

```shell
npm install @obinexusltd/objc-polycall
```

The npm package publishes and indexes every project source directory:
`src`, `include`, `generated`, `examples`, `tests`, and `scripts`. All entries
in `package.json` are relative to the package root.

```javascript
const objcPolycall = require('@obinexusltd/objc-polycall');

console.log(objcPolycall.directories.src.relative);
console.log(objcPolycall.directories.include.relativeFiles);
console.log(objcPolycall.resolve('examples', 'main.m'));
```

Each directory index provides its relative name, absolute root, absolute file
list, and portable relative file list.

## Requirements

- macOS Foundation or a compatible GNUstep Foundation implementation
- Clang with Objective-C and ARC support
- libpolycall 1.5 development library and headers
- GNU Make

## Build

Build and test the portable native forwarding shim:

```shell
make
make test
```

Build the Objective-C static library on macOS:

```shell
make objc OBJC=clang
```

GNUstep users can override `OBJCFLAGS` and `FOUNDATION_LIBS` with the values
reported by `gnustep-config`.

## API

```objective-c
#import <OBNPolycall.h>

int32_t status = [OBNPolycall rawStatusForConfigAtPath:@"objc-polycallrc"];

NSError *error = nil;
BOOL ok = [OBNPolycall runConfigAtPath:@"objc-polycallrc" error:&error];
```

- `rawStatusForConfigAtPath:` returns the exact libpolycall status.
- `runConfigAtPath:error:` returns `YES` for zero and populates `NSError` for a
  non-zero status.
- `OBNPolycallErrorDomain` identifies binding errors.
- Configuration paths are passed as UTF-8.

See [`examples/main.m`](examples/main.m) for a runnable command-line example.

## Verification

```shell
npm test
```

The default suite verifies exact path forwarding, the validation flag, status
propagation, UTF-8 conversion, `NSError` mapping, every relative npm directory,
safe path containment, and package completeness.

On a Foundation-capable Objective-C host:

```shell
npm run test:objc
```

## Package layout

- `src/` — Objective-C implementation and native adapter
- `include/` — public headers and Clang module map
- `generated/polycall/` — minimal generated core FFI declaration
- `examples/` — command-line Objective-C example and configuration
- `tests/` — portable C, Objective-C, and npm package tests
- `scripts/` — thin-adapter audits

## Author and license

Copyright © 2026 Nnamdi Michael Okpala
<okpalan@protonmail.com>.

Released under the [MIT License](LICENSE).
