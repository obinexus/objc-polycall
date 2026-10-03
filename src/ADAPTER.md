# Objective-C adapter

`OBNPolycall.m` provides the Foundation API over the core's installed
`<polycall.h>` (found with `pkg-config polycall`); every method calls one C
function of the binding ABI v1 and turns its status into an `NSError`
(status, `polycall_strerror` name, `polycall_last_error` detail).

`objc_polycall.c` is the documented native entry point: it forwards the UTF-8
path to `polycall_ffi_run_config(config_path, 1)` and returns the status
unchanged (`objc_polycall_run_config_strict` passes the strict flag).

No configuration parsing or runtime policy belongs in this binding.
