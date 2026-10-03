/*
 * MOCK of polycall_ffi_run_config for the adapter unit test of the C
 * forwarding shim (tests/objc_polycall_adapter_test.c). It is NOT the core:
 * real-core behaviour is tested by tests/test_objc_polycall.m against the
 * installed libpolycall. The declaration comes from the real <polycall.h>,
 * so the shim is compiled against the real signature.
 */
#include "polycall_ffi_mock.h"

#include <polycall.h>

#include <stdlib.h>
#include <string.h>

static int mock_status;
static int mock_calls;
static int mock_run;
static char mock_config[1024];

int polycall_ffi_run_config(const char *config_path, int run) {
    ++mock_calls;
    mock_run = run;

    if (config_path) {
        strncpy(mock_config, config_path, sizeof(mock_config) - 1);
        mock_config[sizeof(mock_config) - 1] = '\0';
    } else {
        mock_config[0] = '\0';
    }
    return mock_status;
}

void polycall_ffi_mock_reset(void) {
    mock_status = 0;
    mock_calls = 0;
    mock_run = -1;
    mock_config[0] = '\0';
}

void polycall_ffi_mock_return_status(int status) {
    mock_status = status;
}

int polycall_ffi_mock_call_count(void) {
    return mock_calls;
}

int polycall_ffi_mock_last_run(void) {
    return mock_run;
}

const char *polycall_ffi_mock_last_config(void) {
    return mock_config;
}
