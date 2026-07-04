CC ?= gcc
AR ?= ar
OBJC ?= clang

CPPFLAGS ?=
CPPFLAGS += -Iinclude -Igenerated
CFLAGS ?= -O2
CFLAGS += -std=c11 -Wall -Wextra -Wpedantic
OBJCFLAGS ?= -O2 -fobjc-arc -Wall -Wextra
FOUNDATION_LIBS ?= -framework Foundation

BUILD_DIR := build
LIB_DIR := lib
ADAPTER_OBJ := $(BUILD_DIR)/objc_polycall.o
OBJC_OBJ := $(BUILD_DIR)/OBNPolycall.o
STATIC_LIB := $(LIB_DIR)/libobjc_polycall.a
FOUNDATION_LIB := $(LIB_DIR)/libObjCPolycall.a
TEST_BIN := $(BUILD_DIR)/objc_polycall_adapter_test
OBJC_TEST_BIN := $(BUILD_DIR)/objc_polycall_test

ifeq ($(OS),Windows_NT)
EXE_EXT := .exe
TEST_BIN := $(TEST_BIN)$(EXE_EXT)
OBJC_TEST_BIN := $(OBJC_TEST_BIN)$(EXE_EXT)
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

$(ADAPTER_OBJ): src/objc_polycall.c include/objc_polycall.h generated/polycall/polycall_ffi.h | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -MMD -MP -c $< -o $@

$(STATIC_LIB): $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

$(TEST_BIN): src/objc_polycall.c tests/polycall_ffi_mock.c tests/objc_polycall_adapter_test.c | $(BUILD_DIR)
	$(CC) $(CPPFLAGS) -Itests $(CFLAGS) $^ -o $@

.PHONY: test
test: $(TEST_BIN)
	$(TEST_BIN)

$(OBJC_OBJ): src/OBNPolycall.m include/OBNPolycall.h include/objc_polycall.h | $(BUILD_DIR)
	$(OBJC) $(CPPFLAGS) $(OBJCFLAGS) -MMD -MP -c $< -o $@

$(FOUNDATION_LIB): $(OBJC_OBJ) $(ADAPTER_OBJ) | $(LIB_DIR)
	$(AR) rcs $@ $^

.PHONY: objc
objc: $(FOUNDATION_LIB)

.PHONY: test-objc
test-objc: | $(BUILD_DIR)
	$(OBJC) $(CPPFLAGS) -Itests $(OBJCFLAGS) \
		src/OBNPolycall.m src/objc_polycall.c tests/polycall_ffi_mock.c \
		tests/test_objc_polycall.m $(FOUNDATION_LIBS) -o $(OBJC_TEST_BIN)
	$(OBJC_TEST_BIN)

.PHONY: example
example: | $(BUILD_DIR)
ifeq ($(OS),Windows_NT)
	@if "$(strip $(POLYCALL_LDFLAGS))"=="" (echo Set POLYCALL_LDFLAGS to the libpolycall linker flags & exit /b 2)
else
	@test -n "$(POLYCALL_LDFLAGS)" || (echo "Set POLYCALL_LDFLAGS to the libpolycall linker flags" && exit 2)
endif
	$(OBJC) $(CPPFLAGS) $(OBJCFLAGS) src/OBNPolycall.m \
		src/objc_polycall.c examples/main.m $(POLYCALL_LDFLAGS) \
		$(FOUNDATION_LIBS) -o $(BUILD_DIR)/objc-polycall-example$(EXE_EXT)

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

-include $(ADAPTER_OBJ:.o=.d) $(OBJC_OBJ:.o=.d)
