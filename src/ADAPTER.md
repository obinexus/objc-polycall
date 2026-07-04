# Objective-C adapter

`OBNPolycall.m` provides the Foundation API. `objc_polycall.c` forwards the
UTF-8 path to `polycall_ffi_run_config(config_path, 1)` and returns the status
unchanged.

No configuration parsing or runtime policy belongs in this binding.
