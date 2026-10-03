# @obinexusltd/objc-polycall

Objective-C / Foundation binding for [Polycall](https://github.com/obinexus/polycall):
the binding ABI v1 of the Polycall C library (`polycall.h`, `libpolycall`),
with Cocoa conventions (`NSString`, `NSData`, `NSError`).

Configuration parsing, validation, networking and runtime policy remain in the
core. The Objective-C layer converts `NSString` to UTF-8, `NSData` to
`(pointer, length)`, and maps every non-zero status into an `NSError` that
carries the status code, its `polycall_strerror` name and the
`polycall_last_error` detail.

## Requirements

- The Polycall core **1.1.0 or newer (binding ABI 1)** with its headers and
  pkg-config file (`libpolycall-dev`, or a CMake install of the core), found
  with `pkg-config polycall` (set `PKG_CONFIG_PATH` for a non-default prefix).
- A Foundation implementation:
  - macOS Foundation with clang (ARC), or
  - GNUstep Base: GCC/gobjc with manual reference counting (the Debian/Ubuntu
    packages `gobjc gnustep-devel`), or clang + libobjc2 (add `-fobjc-arc`).
  The sources compile under both ARC and MRC.
- GNU Make.

Tested: Linux x86_64 with GNUstep Base 1.28 and GCC 12 (Debian 12). macOS is
supported by the sources and the Makefile defaults but has not been tested
(no macOS host was available). On Windows only the portable C shim has been
built and tested (MinGW-w64 UCRT64 and MSVC, against `libpolycall.dll` /
`polycall.dll`); the Objective-C layer needs an Objective-C + Foundation
toolchain for Windows (e.g. GNUstep for MSYS2), which was not available.

## Build

```shell
export PKG_CONFIG_PATH=/opt/polycall/lib/pkgconfig   # if the core is not in a default prefix
make            # C forwarding shim: lib/libobjc_polycall.a
make objc       # Foundation library: lib/libObjCPolycall.a
make example    # build/objc-polycall-example
```

On macOS the defaults are `clang -fobjc-arc -framework Foundation`; elsewhere
`OBJCFLAGS` / `FOUNDATION_LIBS` come from `gnustep-config`. Override
`OBJC`, `OBJCFLAGS`, `FOUNDATION_LIBS`, `POLYCALL_CFLAGS` or `POLYCALL_LIBS`
as needed.

## API

```objective-c
#import <OBNPolycall.h>

// library / ABI
NSError *error = nil;
if (![OBNPolycall checkABIVersion:&error]) { /* not binding ABI 1: error names the library */ }
NSString *version = [OBNPolycall libraryVersion];          // @"1.1.0"

// configuration -- the documented entry points are strict (run = 1)
int32_t status = [OBNPolycall rawStatusForConfigAtPath:@"objc-polycallrc"];
BOOL ok = [OBNPolycall runConfigAtPath:@"objc-polycallrc" error:&error];
ok = [OBNPolycall runConfigAtPath:@"objc-polycallrc" strict:NO error:&error];  // unknown keys warn
NSString *json = [OBNPolycall describeConfigAtPath:@"Polycallfile" error:&error];

// RPC to `polycall daemon start` / `polycall start` (one round trip, never retried)
NSString *out = [OBNPolycall callEndpoint:@"127.0.0.1:8084" service:@"inventory"
                                operation:@"get" inputJSON:@"{\"item_id\":\"widget-a\"}"
                                timeoutMs:2000 error:&error];

// peer nodes (polycall-peer/1, no broker)
OBNPolycallPeer *alpha = [OBNPolycallPeer peerWithNodeID:@"alpha" bindEndpoint:@"127.0.0.1:0"
                                               authToken:token error:&error];
[alpha registerPeer:@"beta" endpoint:betaEndpoint error:&error];
[alpha ping:@"beta" timeoutMs:2000 error:&error];
[alpha sendData:payload toPeer:@"beta" messageID:@"m-1" timeoutMs:2000 error:&error];
OBNPolycallMessage *m = [beta receiveWithTimeoutMs:2000 error:&error];  // m.sender, m.messageID, m.payload
[beta cancel:&error];   // wakes receives blocked on beta (POLYCALL_E_CANCELLED)
[beta close:&error];    // wakes them with POLYCALL_E_CLOSED; a second close fails with INVALID_HANDLE
```

`OBNPolycallPeer` also has `endpoint:`, `nodeID:`, `unregisterPeer:error:`,
`registry:` / `registryJSON:`, `healthJSON:`, `sendString:...` and
`receiveWithTimeoutMs:capacity:error:`. All methods are thread-safe; a
receive blocks only its own thread, and `cancel:` / `close:` from another
thread wake it.

### Errors

`NSError.domain` is `OBNPolycallErrorDomain`, `NSError.code` the Polycall
status (`OBNPolycallStatus...`, e.g. `OBNPolycallStatusTimeout` = -4). The
`userInfo` holds:

| key | value |
| --- | --- |
| `OBNPolycallStatusNameKey` | `polycall_strerror(status)`, e.g. `POLYCALL_E_TIMEOUT: deadline exceeded` |
| `OBNPolycallDetailKey` | `polycall_last_error()` read on the failing thread |
| `OBNPolycallRemoteErrorKey` | for calls: the remote error object JSON, when present |
| `OBNPolycallRequiredSizeKey` | for `POLYCALL_E_TOO_LARGE`: bytes the core asked for |
| `NSLocalizedDescriptionKey` | `"<name> [<status>]: <detail>"` |

A string containing U+0000 cannot cross the C ABI unchanged and is refused
with `POLYCALL_E_INVALID_ARGUMENT` instead of being truncated.

### Loading

The library is linked through pkg-config, so the OS loader resolves
`libpolycall`: a missing library or a 1.0 library without the ABI v1 symbols
stops the program with the loader's message (exit 127, no crash), and a
library reporting another binding ABI makes every API fail with
`POLYCALL_E_UNSUPPORTED` ("binding ABI mismatch", naming the library file).
Nothing the library returns is freed by the binding; a peer handle is
released exactly once (`close:`, or `dealloc` when it was never closed).

## Install the source package

```shell
npm install @obinexusltd/objc-polycall
```

The npm package ships the project sources (`src`, `include`, `examples`,
`tests`, `scripts`, `Makefile`). Its CommonJS entry point only indexes them:

```javascript
const objcPolycall = require('@obinexusltd/objc-polycall');
console.log(objcPolycall.directories.src.relativeFiles);
console.log(objcPolycall.resolve('examples', 'main.m'));
```

Build the native code from the installed package directory with `make`.

## Verification

```shell
npm test            # adapter unit test (mock core), thin-adapter audit, npm index test
make test-real      # REAL core: C shim, Objective-C suite, loader errors
make build/objc_polycall_test && sh tests/valgrind.sh   # memory check (valgrind)
sh tests/run-real-core.sh   # everything above, plus npm pack/install into a clean project
```

The real-core suite needs `libpolycall` and, for the daemon and C-peer
interop checks, the `polycall` CLI on `PATH`; without the CLI those checks
print `SKIP`, never `PASS`. See [tests/TESTS.md](tests/TESTS.md).

## Package layout

- `src/` — Objective-C implementation and the C forwarding shim
- `include/` — public headers and Clang module map
- `examples/` — command-line example and configuration
- `tests/` — real-core suites, loader fixtures, adapter unit test
- `scripts/` — thin-adapter audits

## Author and license

Copyright © 2026 Nnamdi Michael Okpala
<okpalan@protonmail.com>.

Released under the [MIT License](LICENSE).
