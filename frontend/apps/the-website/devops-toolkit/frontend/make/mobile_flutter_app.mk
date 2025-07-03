# --------------------------------
# Mobile Flutter App
# --------------------------------

SHELL := /bin/bash

.PHONY: run-ios run-android \
	build-ios build-android \
	e2e-test-ios e2e-test-android \
	integration-test-ios integration-test-android \
	ci-ios ci-android

# --------------------------------
# Internal Variable Declaration
# --------------------------------

ifndef INCLUDED_FLUTTER_APP_CONFIGURATION
  include devops-toolkit/frontend/make/utils/flutter_app_configuration.mk
endif

# --------------------------------
# Targets
# --------------------------------

ifndef INCLUDED_FLUTTER_APP_TARGETS
  include devops-toolkit/frontend/make/utils/flutter_app_targets.mk
endif

ifndef INCLUDED_ANDROID_APP_CONFIGURATION_TARGETS
  include devops-toolkit/frontend/make/utils/android_app_configuration_targets.mk
endif

ifndef INCLUDED_IOS_APP_CONFIGURATION_TARGETS
  include devops-toolkit/frontend/make/utils/ios_app_configuration_targets.mk
endif

# Run API integration tests (non-UI logic tests) for iOS
integration-test-ios: _ios_app_configuration
	@$(MAKE) _integration-test --no-print-directory PLATFORM=ios GCP_SDK_KEY=$(GCP_IOS_SDK_KEY)

# Run API integration tests (non-UI logic tests) for Android
integration-test-android: _android_app_configuration
	@$(MAKE) _integration-test --no-print-directory PLATFORM=android GCP_SDK_KEY=$(GCP_ANDROID_SDK_KEY)

# Run end-to-end (UI) tests for iOS
e2e-test-ios: _ios_app_configuration
	@$(MAKE) _e2e-test --no-print-directory PLATFORM=ios GCP_SDK_KEY=$(GCP_IOS_SDK_KEY)

# Run end-to-end (UI) tests for Android
e2e-test-android: _android_app_configuration
	@$(MAKE) _e2e-test --no-print-directory PLATFORM=android GCP_SDK_KEY=$(GCP_ANDROID_SDK_KEY)

## Run the app in a specific environment (ENV=dev|dev-test|staging|prod) for ios
run-ios: _ios_app_configuration
	@$(MAKE) _run --no-print-directory PLATFORM=ios GCP_SDK_KEY=$(GCP_IOS_SDK_KEY)

## Run the app in a specific environment (ENV=dev|dev-test|staging|prod) for android
run-android: _android_app_configuration
	@$(MAKE) _run --no-print-directory PLATFORM=android GCP_SDK_KEY=$(GCP_ANDROID_SDK_KEY)

## Build command for Android
build-android: logs _android_app_configuration
	@echo "[INFO] [Build Android] Building for ENV=$(ENV)..."
	@echo "[INFO] [Build Android] Setting up environment..."
	@if [ "$(ENV)" = "$(DEV_TEST_ENV)" ]; then \
		echo "[WARN] [Build Android] Running ENV=dev-test, backend is not required, setting the domain to 'example.com'."; \
		export CURRENT_BACKEND_DOMAIN="example.com"; \
	fi;	\
	backend_export="$$( $(MAKE) _export_current_backend_domain --no-print-directory )"; \
	rc=$$?; [ $$rc -eq 0 ] || exit $$rc; \
	eval "$$backend_export"; \
	echo "[INFO] [Build Android] Building..."; \
	set -eo pipefail; \
	flutter build appbundle --release \
		--target lib/main/main_$(ENV).dart --dart-define=CURRENT_BACKEND_DOMAIN=$$CURRENT_BACKEND_DOMAIN \
		--dart-define=GCP_SDK_KEY=$(GCP_ANDROID_SDK_KEY) \
		$(VERBOSE_FLAG) 2>&1 | tee logs/build_android.log; \
	echo "[INFO] [Build Android] Build complete. Check logs/build_android.log for details."

## Build command for iOS
build-ios: logs _ios_app_configuration
	@echo "[INFO] [Build iOS] Building for ENV=$(ENV)..."
	@echo "[INFO] [Build iOS] Setting up environment..."
	@if [ "$(ENV)" = "$(DEV_TEST_ENV)" ]; then \
		echo "[WARN] [Build iOS] Running ENV=dev-test, backend is not required, setting the domain to 'example.com'."; \
		export CURRENT_BACKEND_DOMAIN="example.com"; \
	fi;	\
	backend_export="$$( $(MAKE) _export_current_backend_domain --no-print-directory )"; \
	rc=$$?; [ $$rc -eq 0 ] || exit $$rc; \
	eval "$$backend_export"; \
	echo "[INFO] [Build iOS] Building..."; \
	set -eo pipefail; \
	flutter build ipa --release --no-codesign \
		--target lib/main/main_$(ENV).dart --dart-define=CURRENT_BACKEND_DOMAIN=$$CURRENT_BACKEND_DOMAIN \
		--dart-define=GCP_SDK_KEY=$(GCP_IOS_SDK_KEY) \
		$(VERBOSE_FLAG) 2>&1 | tee logs/build_ios.log; \
	echo "[INFO] [Build iOS] Build complete. Check logs/build_ios.log for details."

## CI iOS pipeline: Starts backend, runs both integration and e2e tests, and then shuts down backend
ci-ios::
	@echo "[INFO] [CI] Starting pipeline..."
	@echo "[INFO] [CI] Calling 'down-backend' target to ensure clean state..."
	@$(MAKE) down-backend --no-print-directory
	@echo "[INFO] [CI] Calling 'integration-test-ios' target..."
	@$(MAKE) integration-test-ios --no-print-directory AUTO_LAUNCH_BACKEND=1
	@# $(MAKE) e2e-test-ios --no-print-directory # TODO: implement e2e tests
	@echo "[INFO] [CI] Calling 'down-backend' target..."
	@$(MAKE) down-backend --no-print-directory
	@echo "[INFO] [CI] Pipeline complete."

## CI Android pipeline: Starts backend, runs both integration and e2e tests, and then shuts down backend
ci-android::
	@echo "[INFO] [CI] Starting pipeline..."
	@echo "[INFO] [CI] Calling 'down-backend' target to ensure clean state..."
	@$(MAKE) down-backend --no-print-directory
	@echo "[INFO] [CI] Calling 'integration-test-android' target..."
	@$(MAKE) integration-test-android --no-print-directory AUTO_LAUNCH_BACKEND=1
	@# $(MAKE) e2e-test-android --no-print-directory # TODO: implement e2e tests
	@echo "[INFO] [CI] Calling 'down-backend' target..."
	@$(MAKE) down-backend --no-print-directory
	@echo "[INFO] [CI] Pipeline complete."


INCLUDED_MOBILE_FLUTTER_APP := 1
