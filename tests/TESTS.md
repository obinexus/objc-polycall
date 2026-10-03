# Objective-C tests

| Command | What it runs | Core |
| --- | --- | --- |
| `make test` | `objc_polycall_adapter_test.c`: exact forwarding of the C shim, against `polycall_ffi_mock.c` | **mock** (adapter unit test only) |
| `make verify-dry` | thin-adapter source audit (`scripts/verify-dry.sh` / `.ps1`) | none |
| `npm run test:package` | npm metadata and relative-directory index (`package.test.js`) | none |
| `make test-c-real` | `c_shim_real_test.c`: the C shim alone (valid, missing, invalid, lenient/strict, TLS, non-ASCII path) | real |
| `make test-objc` | `test_objc_polycall.m`: library/ABI, run_config, describe, `call` against a `polycall daemon` (success, errors, deadline, bounds, too-small buffer, concurrency), two peers both directions (empty, UTF-8, binary, 1 MiB, 1 MiB + 1), registry ownership, duplicates, auth, dead peer, backpressure, cancel/close waking a blocked receive, double close / use after close, concurrent senders, interop with the C CLI (`polycall peer serve/send/recv`) | real |
| `make test-loader` | `loader-errors.sh`: example against no library, a 1.0 library without ABI v1 symbols, a library reporting ABI 2 (`fixtures/`) | real + fixtures |
| `sh tests/valgrind.sh` | the Objective-C suite under valgrind memcheck; fails on any error record with a binding or libpolycall frame | real |
| `sh tests/run-real-core.sh` | all of the above plus `npm pack`, install into a clean project, build and run from the installed package | real |

Checks that need the `polycall` CLI print `SKIP` (never `PASS`) when it is
absent; `run-real-core.sh` exits 77 when a prerequisite is missing.
