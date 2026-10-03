/*
 * The C forwarding shim (src/objc_polycall.c) against the REAL libpolycall,
 * with no Objective-C runtime involved, so the native layer can also be
 * checked with toolchains that have no Foundation (e.g. MSVC / MinGW on
 * Windows). Usage: c_shim_real_test <writable temp dir>
 */
#include "objc_polycall.h"

#include <polycall.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if defined(_WIN32)
#include <windows.h>
#endif

static int g_pass, g_fail;

static void check(int ok, const char *what, int got) {
    if (ok) { g_pass++; printf("PASS  %s (status %d)\n", what, got); }
    else { g_fail++; printf("FAIL  %s (status %d)\n", what, got); }
}

/* `path` is UTF-8; on Windows open it through UTF-16 like a host runtime. */
static void write_file(const char *path, const char *text) {
    FILE *f;
#if defined(_WIN32)
    wchar_t wpath[1024];
    if (MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, 1024) <= 0) return;
    f = _wfopen(wpath, L"wb");
#else
    f = fopen(path, "wb");
#endif
    if (f) { fputs(text, f); fclose(f); }
}

int main(int argc, char **argv) {
    char p[1024], ver[32], detail[256];
    const char *dir = argc > 1 ? argv[1] : ".";
    int rc;

    check(polycall_ffi_abi_version() == POLYCALL_FFI_ABI_VERSION, "binding ABI is 1", polycall_ffi_abi_version());
    rc = polycall_ffi_version(ver, (int)sizeof ver);
    check(rc > 0, ver, rc);

    snprintf(p, sizeof p, "%s/objc-polycallrc", dir);
    write_file(p, "log_level=info\nmax_connections=1000\nnetwork_timeout=5000\ntls_enabled=false\n");
    rc = objc_polycall_run_config(p);
    check(rc == POLYCALL_OK, "objc_polycall_run_config(valid) -> OK", rc);

    snprintf(p, sizeof p, "%s/does-not-exist-polycallrc", dir);
    rc = objc_polycall_run_config(p);
    check(rc == POLYCALL_E_NOT_FOUND, "missing file -> NOT_FOUND", rc);

    rc = objc_polycall_run_config("");
    check(rc == POLYCALL_E_INVALID_ARGUMENT, "empty path -> INVALID_ARGUMENT", rc);

    snprintf(p, sizeof p, "%s/bad-polycallrc", dir);
    write_file(p, "max_connections=lots\n");
    rc = objc_polycall_run_config(p);
    polycall_last_error(detail, sizeof detail);
    check(rc == POLYCALL_E_CONFIG && strstr(detail, "max_connections") != NULL,
          "invalid value -> CONFIG with the key in polycall_last_error", rc);

    snprintf(p, sizeof p, "%s/unknown-polycallrc", dir);
    write_file(p, "log_level=info\nmystery_key=1\n");
    rc = objc_polycall_run_config_strict(p, 0);
    check(rc == POLYCALL_OK, "unknown key, lenient -> OK", rc);
    rc = objc_polycall_run_config(p);
    check(rc == POLYCALL_E_CONFIG, "unknown key, documented strict entry point -> CONFIG", rc);

    snprintf(p, sizeof p, "%s/tls-polycallrc", dir);
    write_file(p, "tls_enabled=true\ncert_file=/x/c.pem\nkey_file=/x/k.pem\n");
    rc = objc_polycall_run_config(p);
    check(rc == POLYCALL_E_UNSUPPORTED, "tls_enabled=true strict -> UNSUPPORTED", rc);

    /* "Ünicødé-日本-polycallrc" */
    snprintf(p, sizeof p, "%s/\xc3\x9cnic\xc3\xb8" "d\xc3\xa9-\xe6\x97\xa5\xe6\x9c\xac-polycallrc", dir);
    write_file(p, "log_level=info\nmax_connections=10\n");
    rc = objc_polycall_run_config(p);
    check(rc == POLYCALL_OK, "non-ASCII UTF-8 path -> OK", rc);

    printf("--- c shim against libpolycall %s: %d passed, %d failed ---\n", ver, g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
