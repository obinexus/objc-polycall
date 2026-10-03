# objc-polycall -- Objective-C / Foundation binding of the Polycall binding ABI v1.
#
# The core is found through pkg-config (polycall.pc, installed by the core):
#   PKG_CONFIG_PATH=/opt/polycall/lib/pkgconfig make test-real
# Override POLYCALL_CFLAGS / POLYCALL_LIBS to point elsewhere.
#
# Objective-C toolchains:
#   macOS:   clang + ARC + Foundation.framework (defaults below)
#   GNUstep: OBJCFLAGS / FOUNDATION_LIBS from gnustep-config (defaults below);
#            GCC (gobjc) builds with manual reference counting, clang with
#            libobjc2 can add -fobjc-arc. The sources support both.

CC ?= cc
AR ?= ar
PKG_CONFIG ?= pkg-config

POLYCALL_CFLAGS ?= $(shell $(PKG_CONFIG) --cflags polycall)
POLYCALL_LIBS ?= $(shell $(PKG_CONFIG) --libs polycall)
# kept for compatibility with the previous `make example POLYCALL_LDFLAGS=...`
POLYCALL_LDFLAGS ?= $(POLYCALL_LIBS)

CPPFLAGS ?=
CPPFLAGS += -Iinclude $(POLYCALL_CFLAGS)
CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic

ifeq ($(OS),Windows_NT)
UNAME_S := Windows
else
UNAME_S := $(shell uname -s)
endif

ifeq ($(UNAME_S),Darwin)
OBJC ?= clang
OBJCFLAGS ?= -O2 -fobjc-arc -Wall -Wextra
FOUNDATION_LIBS ?= -framework Foundation
else
GNUSTEP_CONFIG ?= gnustep-config
OBJC ?= $(CC)
OBJCFLAGS ?= $(filter-out -MMD -MP,$(shell $(GNUSTEP_CONFIG) --objc-flags 2>/dev/null)) -Wall
FOUNDATION_LIBS ?= $(shell $(GNUSTEP_CONFIG) --base-libs 2>/dev/null)
endif

BUILD_DIR := build
LIB_DIR := lib
ADAPTER_OBJ := $(BUILD_DIR)/objc_polycall.o
OBJC_OBJ := $(BUILD_DIR)/OBNPolycall.o
STATIC_LIB := $(LIB_DIR)/libobjc_polycall.a
FOUNDATION_LIB := $(LIB_DIR)/libObjCPolycall.a
TEST_BIN := $(BUILD_DIR)/objc_polycall_adapter_test
OBJC_TEST_BIN := $(BUILD_DIR)/objc_polycall_test
EXAMPLE_BIN := $(BUILD_DIR)/objc-polycall-example

ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
TEST_BIN := $(TEST_BIN)$(EXE_EXT)
OBJC_TEST_BIN := $(OBJC_TEST_BIN)$(EXE_EXT)
EXAMPLE_BIN := $(EXAMPLE_BIN)$(EXE_EXT)
endif

.DEFAULT_GOAL := all

.PHONY: all
all: $(STATIC_LIB)

$(BUILD_DIR) $(LIB_DIR):
ifeq ($(OS),Windows_NT)
	@if not exist "$@" mkdir "$@"
else
	@mkdir -p $@
endif

$(ADAPTER_OBJ): src/objc_polycall.c include/objc_polycall.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(STATIC_LIB): $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

# Adapter unit test of the C forwarding shim against a MOCK core (no libpolycall).
$(TEST_BIN): src/objc_polycall.c tests/polycall_ffi_mock.c tests/objc_polycall_adapter_test.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) -Itests $(CFLAGS) $^ -o $@

.PHONY: test
test: $(TEST_BIN)
	$(TEST_BIN)

$(OBJC_OBJ): src/OBNPolycall.m include/OBNPolycall.h include/objc_polycall.h | $(BUILD_DIR)
	$(OBJC) $(CPPFLAGS) $(OBJCFLAGS) -c $< -o $@

$(FOUNDATION_LIB): $(OBJC_OBJ) $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

.PHONY: objc
objc: $(FOUNDATION_LIB)

# Objective-C test suite against the REAL libpolycall (and the polycall CLI).
$(OBJC_TEST_BIN): src/OBNPolycall.m $(ADAPTER_OBJ) tests/test_objc_polycall.m include/OBNPolycall.h | $(BUILD_DIR)
	$(OBJC) $(CPPFLAGS) $(OBJCFLAGS) src/OBNPolycall.m $(ADAPTER_OBJ) \
		tests/test_objc_polycall.m $(POLYCALL_LIBS) $(FOUNDATION_LIBS) $(LDLIBS) -o $@

.PHONY: test-objc
test-objc: $(OBJC_TEST_BIN)
	$(OBJC_TEST_BIN)

$(EXAMPLE_BIN): src/OBNPolycall.m $(ADAPTER_OBJ) examples/main.m include/OBNPolycall.h | $(BUILD_DIR)
	$(OBJC) $(CPPFLAGS) $(OBJCFLAGS) src/OBNPolycall.m $(ADAPTER_OBJ) examples/main.m \
		$(POLYCALL_LDFLAGS) $(FOUNDATION_LIBS) $(LDLIBS) -o $@

.PHONY: example
example: $(EXAMPLE_BIN)

# Loader behaviour: no library, a 1.0 library without ABI v1 symbols, ABI 2.
.PHONY: test-loader
test-loader: $(EXAMPLE_BIN)
	sh tests/loader-errors.sh $(EXAMPLE_BIN)

# The C forwarding shim alone against the REAL libpolycall (no Foundation).
C_REAL_TEST_BIN := $(BUILD_DIR)/c_shim_real_test$(EXE_EXT)
$(C_REAL_TEST_BIN): $(ADAPTER_OBJ) tests/c_shim_real_test.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) tests/c_shim_real_test.c $(ADAPTER_OBJ) $(POLYCALL_LIBS) -o $@

.PHONY: test-c-real
test-c-real: $(C_REAL_TEST_BIN)
	$(C_REAL_TEST_BIN) $(BUILD_DIR)

.PHONY: test-real
test-real: test-c-real test-objc test-loader

.PHONY: verify-dry
verify-dry:
ifeq ($(OS),Windows_NT)
	powershell -NoProfile -ExecutionPolicy Bypass -File scripts/verify-dry.ps1
else
	sh scripts/verify-dry.sh
endif

.PHONY: clean
clean:
ifeq ($(OS),Windows_NT)
	@if exist "$(BUILD_DIR)" rmdir /s /q "$(BUILD_DIR)"
	@if exist "$(LIB_DIR)" rmdir /s /q "$(LIB_DIR)"
else
	rm -rf $(BUILD_DIR) $(LIB_DIR)
endif

-include $(ADAPTER_OBJ:.o=.d)
