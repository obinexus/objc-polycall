#ifndef OBJC_POLYCALL_H
#define OBJC_POLYCALL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The binding's documented native entry point: the exact status of
 * polycall_ffi_run_config(config_path, 1) (validate for running). */
int32_t objc_polycall_run_config(const char *config_path);

/* polycall_ffi_run_config(config_path, strict ? 1 : 0). */
int32_t objc_polycall_run_config_strict(const char *config_path, int strict);

#ifdef __cplusplus
}
#endif

#endif
