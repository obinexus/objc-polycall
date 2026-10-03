/*
 * Adapter unit test of the C forwarding shim against a MOCK core
 * (tests/polycall_ffi_mock.c). It checks exact forwarding only; behaviour of
 * the real library is covered by tests/test_objc_polycall.m.
 */
#include "objc_polycall.h"
#include "polycall_ffi_mock.h"

#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

int main(void) {
    const char *config_path = "objc-polycallrc";
    int32_t status;

    polycall_ffi_mock_reset();
    status = objc_polycall_run_config(config_path);

    assert(status == 0);
    assert(polycall_ffi_mock_call_count() == 1);
    assert(polycall_ffi_mock_last_run() == 1);
    assert(strcmp(polycall_ffi_mock_last_config(), config_path) == 0);

    polycall_ffi_mock_return_status(-13);
    status = objc_polycall_run_config(config_path);
    assert(status == -13);
    assert(polycall_ffi_mock_call_count() == 2);

    polycall_ffi_mock_return_status(0);
    status = objc_polycall_run_config_strict("lenient-polycallrc", 0);
    assert(status == 0);
    assert(polycall_ffi_mock_last_run() == 0);
    assert(strcmp(polycall_ffi_mock_last_config(), "lenient-polycallrc") == 0);
    status = objc_polycall_run_config_strict("strict-polycallrc", 7);
    assert(polycall_ffi_mock_last_run() == 1);
    assert(polycall_ffi_mock_call_count() == 4);

    puts("objc-polycall native adapter unit test (mock core): PASS");
    return 0;
}
