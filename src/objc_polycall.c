#include "objc_polycall.h"
#include "polycall/polycall_ffi.h"

int32_t objc_polycall_run_config(const char *config_path) {
    return (int32_t)polycall_ffi_run_config(config_path, 1);
}
