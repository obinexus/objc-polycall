#include "objc_polycall.h"

/* The core's installed public header (pkg-config --cflags polycall). */
#include <polycall.h>

int32_t objc_polycall_run_config(const char *config_path) {
    return (int32_t)polycall_ffi_run_config(config_path, 1);
}

int32_t objc_polycall_run_config_strict(const char *config_path, int strict) {
    return (int32_t)polycall_ffi_run_config(config_path, strict ? 1 : 0);
}
