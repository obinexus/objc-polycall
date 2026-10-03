# TODO — objc-polycall

Status: Objective-C/Foundation adapter over the real Polycall binding ABI v1
(`polycall >= 1.1.0`), tested on Linux with GNUstep.

- [x] Publishable `@obinexusltd/objc-polycall` npm source package
- [x] Relative npm indexes for every project source directory
- [x] Real `<polycall.h>` via pkg-config (stub `generated/polycall_ffi.h` removed)
- [x] Foundation API: ABI check, run_config (strict/lenient), describe, call,
      `OBNPolycallPeer`, `NSError` with status / name / detail
- [x] UTF-8 `NSString` conversion, binary `NSData` payloads
- [x] Exact `polycall_ffi_run_config(config_path, 1)` forwarding (documented entry point)
- [x] Real-core Objective-C suite, loader checks, valgrind memory check (GNUstep, Linux)
- [x] Thin-adapter source audit for Windows and POSIX shells
- [ ] Exercise the Objective-C tests on macOS (clang + ARC) — needs a macOS host
- [ ] Exercise the Objective-C layer on Windows (GNUstep for MSYS2 or clang + libobjc2)
- [ ] Publish signed platform-native artifacts

Do not add configuration parsing or runtime policy here; adapt the core only.
