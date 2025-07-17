# -----------------------------------------------------------------------------
# Fastlane Configuration Targets
# -----------------------------------------------------------------------------
SHELL := /bin/bash

.PHONY: 

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif


# ------------------------------
# Targets
# ------------------------------

ifndef INCLUDED_APP_SECRETS_JSON
  include $(DEVOPS_TOOLKIT_PATH)/shared/make/utils/app_secrets_json.mk
endif

_export_ios_fastlane_vars:
	@echo "[INFO] [Export iOS Fastlane Vars] Exporting iOS Fastlane environment variables..."
	$(eval export APP_IDENTIFIER := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.APP_IDENTIFIER'))
	$(eval export APPLE_ID := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.APPLE_ID'))
	$(eval export MATCH_PASSWORD := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.MATCH_PASSWORD'))
	$(eval export MATCH_GIT_BASIC_AUTH := $(shell echo -n "$(shell echo '$(APP_SECRETS_JSON)' | jq -r '.USERNAME'):$(shell echo '$(APP_SECRETS_JSON)' | jq -r '.PAT')" | base64))
	$(eval export APP_STORE_CONNECT_API_KEY_ID := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.APP_STORE_CONNECT_API_KEY_ID'))
	$(eval export APP_STORE_CONNECT_ISSUER_ID := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.APP_STORE_CONNECT_ISSUER_ID'))
	$(eval export APP_STORE_CONNECT_API_KEY_KEY := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.APP_STORE_CONNECT_API_KEY_BASE64'))
	$(eval export DEVELOPMENT_TEAM := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.DEVELOPMENT_TEAM'))
	@echo "[INFO] [Export iOS Fastlane Vars] iOS Fastlane environment variables exported."

_export_android_fastlane_vars:
	@echo "[INFO] [Export Android Fastlane Vars] Exporting Android Fastlane environment variables..."
	$(eval export APP_IDENTIFIER_ANDROID := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.APP_IDENTIFIER_ANDROID'))
	$(eval export GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64 := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_BASE64'))
ifndef ANDROID_RELEASE_TRACK
	$(error ANDROID_RELEASE_TRACK environment variable is required but not set)
endif
	@echo "[INFO] [Export Android Fastlane Vars] Android Fastlane environment variables exported."

_android_fastlane_configuration: _app_secrets_json _export_android_fastlane_vars

_ios_fastlane_configuration: _app_secrets_json _export_ios_fastlane_vars


INCLUDED_FASTLANE_CONFIGURATION_TARGETS := 1

