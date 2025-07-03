# -----------------------------------------------------------------------------
# Android Keystore Setup Targets
# -----------------------------------------------------------------------------
# Makefile snippet to fetch Android Keystore from secrets (APP_SECRETS_JSON),
# decode it into a file, and export environment variables for Gradle.
#
# This file should be included in the root Makefile.
# -----------------------------------------------------------------------------

SHELL := /bin/bash

.PHONY: _export_android_keystore_vars


# ------------------------------
# Targets
# ------------------------------ 

ifndef INCLUDED_APP_SECRETS_JSON
  include devops-toolkit/shared/make/utils/app_secrets_json.mk
endif

/tmp/upload-keystore.p12:
	@echo "[INFO] [Upload Keystore File] Fetching Android keystore from secrets..."
	@echo '$(APP_SECRETS_JSON)' | jq -r '.KEYSTORE' | base64 --decode > /tmp/upload-keystore.p12
	@chmod 600 /tmp/upload-keystore.p12
	@echo "[INFO] [Upload Keystore File] Android keystore file created and permissions set."

_export_android_keystore_vars:
	@echo "[INFO] [Export Android Keystore Vars] Exporting Android keystore environment variables..."
	$(eval export ANDROID_KEYSTORE_PATH:=/tmp/upload-keystore.p12)
	$(eval export ANDROID_KEYSTORE_PASSWORD:=$(shell echo '$(APP_SECRETS_JSON)' | jq -r '.KEYSTORE_PASS'))
	$(eval export ANDROID_KEY_ALIAS:=upload)
	$(eval export ANDROID_KEY_PASSWORD:=$(shell echo '$(APP_SECRETS_JSON)' | jq -r '.KEYSTORE_PASS'))
	@echo "[INFO] [Export Android Keystore Vars] Android keystore environment variables exported."

_android_keystore_configuration: _app_secrets_json /tmp/upload-keystore.p12 _export_android_keystore_vars


INCLUDED_ANDROID_KEYSTORE_CONFIGURATION_TARGETS := 1
