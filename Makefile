# iACE2 — management entry points. See project-plan.md §5.
# Targets for later phases skip themselves with a note until their inputs exist.

# App version, from the VERSION file (MAJOR, MINOR, PATCH, BUILD). It overrides the version
# in pubspec.yaml for release builds.
include VERSION
VERSION_NAME := $(MAJOR).$(MINOR).$(PATCH)
VERSION_CODE := $(BUILD)
VERSION_FLAGS := --build-name=$(VERSION_NAME) --build-number=$(VERSION_CODE)

# Google Play upload key (see tool/android_keystore.sh)
KEYSTORE ?= $(HOME)/.android-keys/iace-upload.jks
ANDROID_KEY_PROPERTIES := android/key.properties

FLUTTER ?= flutter
DART    ?= dart
CC      ?= cc
CFLAGS  ?= -std=c11 -O2 -Wall -Wextra

NATIVE_SRC   := native/src
NATIVE_INC   := native/include
NATIVE_TEST  := native/test
BUILD_DIR    := build/native

CORE_SOURCES := $(filter-out $(NATIVE_SRC)/z80ops.c $(NATIVE_SRC)/cbops.c $(NATIVE_SRC)/edops.c,$(wildcard $(NATIVE_SRC)/*.c))
ifeq ($(shell uname),Darwin)
CORE_LIBS    := -framework CoreFoundation -framework CoreAudio -framework AudioToolbox
else
CORE_LIBS    := -lm -lpthread -ldl
endif
TEST_SOURCES := $(wildcard $(NATIVE_TEST)/*.c)
C_FORMAT_FILES := $(wildcard $(NATIVE_SRC)/ace_core.c $(NATIVE_SRC)/ace_internal.h $(NATIVE_SRC)/audio.c $(NATIVE_SRC)/keyboard.c $(NATIVE_INC)/*.h $(NATIVE_TEST)/*.c)

.DEFAULT_GOAL := help
.PHONY: help setup gen ffigen drift core core-test core-test-ubsan test flutter-test integration-test analyze format \
        run-ios run-android build-ios build-android keystore version assets db-schema-dump db-migration-test clean

help: ## List targets
	@grep -hE '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-18s\033[0m %s\n",$$1,$$2}'

setup: ## Fetch packages and check the toolchain
	$(FLUTTER) pub get
	$(FLUTTER) doctor
	@if [ -d ios ] && command -v pod >/dev/null; then cd ios && pod install --repo-update || true; fi

gen: ffigen drift ## Run all code generators

ffigen: ## Generate Dart FFI bindings from native/include/ace_api.h
	$(DART) run tool/ffigen.dart

drift: ## Generate drift database code
	@if grep -q '^  drift:' pubspec.yaml; then $(DART) run build_runner build --delete-conflicting-outputs; \
	else echo "drift: not added yet (Phase 5)"; fi

core: ## Build the C core for the host
	@if [ -n "$(CORE_SOURCES)" ]; then mkdir -p $(BUILD_DIR) && \
	$(CC) $(CFLAGS) -I$(NATIVE_INC) -I$(NATIVE_SRC) -shared -fPIC -o $(BUILD_DIR)/libace.dylib $(CORE_SOURCES) $(CORE_LIBS); \
	else echo "core: no C sources yet (Phase 1)"; fi

core-test: ## Build and run the C unit tests on the host
	@if [ -n "$(TEST_SOURCES)" ]; then mkdir -p $(BUILD_DIR) && \
	for t in $(TEST_SOURCES); do \
	  n=$$(basename $$t .c); \
	  $(CC) $(CFLAGS) -I$(NATIVE_INC) -I$(NATIVE_SRC) -o $(BUILD_DIR)/$$n $$t $(CORE_SOURCES) $(CORE_LIBS) || exit 1; \
	  (cd $(NATIVE_TEST) && ../../$(BUILD_DIR)/$$n) || exit 1; \
	done; \
	else echo "core-test: no C tests yet (Phase 1)"; fi

core-test-ubsan: ## Run the C unit tests with UndefinedBehaviorSanitizer (ASan hangs on this macOS setup)
	$(MAKE) core-test CFLAGS="-std=c11 -O1 -g -Wall -Wextra -fsanitize=undefined -fno-sanitize-recover=undefined"

flutter-test: ## Run Dart/Flutter tests (unit, widget, migrations)
	$(FLUTTER) test

test: core-test flutter-test ## Run all tests

integration-test: ## Run integration tests on a device or simulator (DEVICE=<id>, see `flutter devices`)
	@if [ -z "$(DEVICE)" ]; then echo "Set DEVICE=<id> (see: flutter devices)"; exit 1; fi
	$(FLUTTER) test integration_test -d "$(DEVICE)"

analyze: ## Static analysis
	$(FLUTTER) analyze

format: ## Format Dart and (non-vendored) C code
	$(DART) format lib test $(wildcard integration_test tool hook)
	@if [ -n "$(C_FORMAT_FILES)" ] && command -v clang-format >/dev/null; then clang-format -i $(C_FORMAT_FILES); fi

run-ios: ## Run on an iPad (device or simulator)
	$(FLUTTER) run -d "$${DEVICE:-iPad}"

run-android: ## Run on an Android tablet (device or emulator)
	$(FLUTTER) run -d "$${DEVICE:-android}"

build-ios: ## Build the iOS archive (.ipa), versioned from VERSION
	$(FLUTTER) build ipa --release $(VERSION_FLAGS)

build-android: ## Build the Android app bundle (.aab), versioned from VERSION, signed with the upload key
	@test -f $(ANDROID_KEY_PROPERTIES) || { echo "No $(ANDROID_KEY_PROPERTIES): run 'make keystore' first (a Play upload needs the upload key)."; exit 1; }
	$(FLUTTER) build appbundle --release $(VERSION_FLAGS)

keystore: ## Create the Google Play upload key and android/key.properties (asks for a password)
	@tool/android_keystore.sh $(KEYSTORE)

version: ## Show the version from VERSION used for builds
	@echo "$(VERSION_NAME) ($(VERSION_CODE))"

assets: ## Convert original iACE resources into assets/ (annotations, keyboard map, tapes)
	@if [ -d tool ] && ls tool/*.py >/dev/null 2>&1; then for s in tool/*.py; do python3 $$s || exit 1; done; \
	else echo "assets: no converters yet (Phases 4, 5, 7)"; fi

db-schema-dump: ## Save the current drift schema to drift_schemas/
	@if grep -q '^  drift:' pubspec.yaml; then \
	$(DART) run drift_dev make-migrations; \
	else echo "db-schema-dump: drift not added yet (Phase 5)"; fi

db-migration-test: ## Run the generated drift migration tests
	@if [ -d test/drift ]; then $(FLUTTER) test test/drift; \
	else echo "db-migration-test: no migration tests yet (Phase 5)"; fi

clean: ## Remove build outputs
	$(FLUTTER) clean
	rm -rf $(BUILD_DIR)
