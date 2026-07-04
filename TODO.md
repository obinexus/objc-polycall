# TODO — objc-polycall

Status: implemented thin Objective-C/Foundation adapter for libpolycall 1.5.

- [x] Publishable `@obinexusltd/objc-polycall` npm source package
- [x] Relative npm indexes for every project source directory
- [x] Foundation API with raw status and `NSError` variants
- [x] UTF-8 `NSString` conversion
- [x] Exact `polycall_ffi_run_config(config_path, 1)` forwarding
- [x] Portable native test and Objective-C smoke test
- [x] Thin-adapter source audit for Windows and POSIX shells
- [ ] Exercise Objective-C tests in macOS and GNUstep release CI
- [ ] Publish signed platform-native artifacts

Do not add configuration parsing or runtime policy here; adapt the core only.
