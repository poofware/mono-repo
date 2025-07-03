# -----------------------------------------------------------------------------
# Google Cloud Configuration Targets
# -----------------------------------------------------------------------------
SHELL := /bin/bash

.PHONY: _export_android_gcp_vars _export_ios_gcp_vars \
	_android_gcp_configuration _ios_gcp_configuration


# ------------------------------
# Targets
# ------------------------------

ifndef INCLUDED_APP_SECRETS_JSON
  include devops-toolkit/shared/make/utils/app_secrets_json.mk
endif

_export_android_gcp_vars:
	@echo "[INFO] [Export Google Cloud Vars] Exporting Android Google Cloud environment variables..."
	$(eval export GCP_ANDROID_SDK_KEY := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.GCP_ANDROID_SDK_KEY'))
	@echo "[INFO] [Export Google Cloud Vars] Android Google Cloud environment variables exported."

_export_ios_gcp_vars:
	@echo "[INFO] [Export Google Cloud Vars] Exporting iOS Google Cloud environment variables..."
	$(eval export GCP_IOS_SDK_KEY := $(shell echo '$(APP_SECRETS_JSON)' | jq -r '.GCP_IOS_SDK_KEY'))
	@echo "[INFO] [Export Google Cloud Vars] iOS Google Cloud environment variables exported."

_android_gcp_configuration: _app_secrets_json _export_android_gcp_vars

_ios_gcp_configuration: _app_secrets_json _export_ios_gcp_vars


INCLUDED_GCP_CONFIGURATION_TARGETS := 1
