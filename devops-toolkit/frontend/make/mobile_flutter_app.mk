# --------------------------------
# Mobile Flutter App
# --------------------------------

SHELL := /bin/bash

.PHONY: run-ios run-android \
	build-ios build-android \
	e2e-test-ios e2e-test-android \
	integration-test-ios integration-test-android \
	ci-ios ci-android

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif


# --------------------------------
# Internal Variable Declaration
# --------------------------------

ifndef INCLUDED_FLUTTER_APP_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/frontend/make/utils/flutter_app_configuration.mk
endif

# Default to 'internal' track, can be overridden
ANDROID_RELEASE_TRACK ?= internal

# --------------------------------
# Targets
# --------------------------------

ifndef INCLUDED_FLUTTER_APP_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/frontend/make/utils/flutter_app_targets.mk
endif

ifndef INCLUDED_ANDROID_APP_CONFIGURATION_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/frontend/make/utils/android_app_configuration_targets.mk
endif

ifndef INCLUDED_IOS_APP_CONFIGURATION_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/frontend/make/utils/ios_app_configuration_targets.mk
endif

ifndef INCLUDED_FASTLANE_CONFIGURATION_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/frontend/make/utils/fastlane_configuration_targets.mk
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

## Install iOS dependencies (Flutter, Gems, and Pods)
dependencies-ios:
	@echo "[INFO] [Dependencies iOS] Installing Flutter packages..."
	@flutter pub get
	@echo "[INFO] [Dependencies iOS] Installing Bundler, Gems, and CocoaPods..."
	@cd ios && \
	gem install bundler --no-document && \
	bundle install --jobs 4 --retry 3 && \
	bundle exec pod install

## Install Android dependencies (Flutter and Gems)
dependencies-android:
	@echo "[INFO] [Dependencies Android] Installing Flutter packages..."
	@flutter pub get
	@echo "[INFO] [Dependencies Android] Installing Bundler and Gems..."
	@cd android/fastlane && \
	gem install bundler --no-document && \
	bundle install

## Build command for Android
build-android: logs _android_app_configuration
	@echo "[INFO] [Build Android] Building for ENV=$(ENV)..."
	@echo "[INFO] [Build Android] Setting up environment..."
	@if [ "$(ENV)" = "$(DEV_TEST_ENV)" ]; then \
		echo "[WARN] [Build Android] Running ENV=dev-test, backend is not required, setting the domain to 'example.com'."; \
		export CURRENT_BACKEND_DOMAIN="example.com"; \
	fi;\
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
	fi;\
	backend_export="$$( $(MAKE) _export_current_backend_domain --no-print-directory )"; \
	rc=$$?; [ $$rc -eq 0 ] || exit $$rc; \
	eval "$$backend_export"; \
	echo "[INFO] [Build iOS] Building..."; \
	set -eo pipefail; \
	extra_cmd=ipa; extra_flags="--release"; \
	if [ "$(ENV)" = "$(DEV_ENV)" ] || [ "$(ENV)" = "$(DEV_TEST_ENV)" ]; then \
		echo "[INFO] [Build iOS] ENV=$(ENV) → building without code signing"; \
		extra_cmd=ios; extra_flags="--debug --no-codesign"; \
	fi; \
	flutter build $$extra_cmd $$extra_flags \
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

## Deploy the iOS app (ENV=staging|prod)
## Convention:
## - ENV=staging → TestFlight upload
## - ENV=prod → App Store submission via deliver
## - RELEASE_NOTES is REQUIRED
## - When ENV=prod, IOS_AUTOMATIC_RELEASE must be 0 or 1
deploy-ios: logs _ios_app_configuration _ios_fastlane_configuration
	@echo "[INFO] [Deploy iOS] Deploying for ENV=$(ENV)..."
	@if [ "$(ENV)" != "$(STAGING_ENV)" ] && [ "$(ENV)" != "$(PROD_ENV)" ]; then \
		echo "[ERROR] [Deploy iOS] Invalid ENV: $(ENV). Choose from [$(STAGING_ENV)|$(PROD_ENV)]."; exit 1; \
	fi
	@if [ -z "$(RELEASE_NOTES)" ]; then \
		echo "[ERROR] [Deploy iOS] RELEASE_NOTES is required"; exit 1; \
	fi
	@if [ "$(ENV)" = "$(PROD_ENV)" ]; then \
		if [ -z "$(IOS_AUTOMATIC_RELEASE)" ]; then echo "[ERROR] [Deploy iOS] IOS_AUTOMATIC_RELEASE is required for prod (0 or 1)"; exit 1; fi; \
		if [ "$(IOS_AUTOMATIC_RELEASE)" != "0" ] && [ "$(IOS_AUTOMATIC_RELEASE)" != "1" ]; then echo "[ERROR] [Deploy iOS] IOS_AUTOMATIC_RELEASE must be 0 or 1"; exit 1; fi; \
	fi
	@echo "[INFO] [Deploy iOS] Running Fastlane to build and upload..."
	@cd ios && set -eo pipefail && \
	MAKE_ENV=$(ENV) \
	RELEASE_NOTES=$(RELEASE_NOTES) \
	IOS_AUTOMATIC_RELEASE=$(IOS_AUTOMATIC_RELEASE) \
	bundle exec fastlane ios build_and_upload_to_testflight \
	$(VERBOSE_FLAG) 2>&1 | tee ../logs/deploy_ios_$(ENV).log

## Deploy the Android app to the Play Store (ENV=staging|prod)
## Convention:
## - Track is derived from ENV: prod → beta, otherwise → internal
## - RELEASE_NOTES is REQUIRED (en-US only)
deploy-android: logs _android_app_configuration _android_fastlane_configuration
	@echo "[INFO] [Deploy Android] Deploying for ENV=$(ENV)..."
	@if [ "$(ENV)" != "$(STAGING_ENV)" ] && [ "$(ENV)" != "$(PROD_ENV)" ]; then \
		echo "[ERROR] [Deploy Android] Invalid ENV: $(ENV). Choose from [$(STAGING_ENV)|$(PROD_ENV)]."; exit 1; \
	fi
	@if [ -z "$(RELEASE_NOTES)" ]; then \
		echo "[ERROR] [Deploy Android] RELEASE_NOTES is required"; exit 1; \
	fi
	@echo "[INFO] [Deploy Android] Running Fastlane to build and upload to Google Play..."
	@cd android/fastlane && set -eo pipefail && \
	MAKE_ENV=$(ENV) \
	RELEASE_NOTES=$(RELEASE_NOTES) \
	bundle exec fastlane android build_and_upload_to_playstore \
	$(VERBOSE_FLAG) 2>&1 | tee ../../logs/deploy_android_$(ENV).log

INCLUDED_MOBILE_FLUTTER_APP := 1
