# -----------------------------------------------------------------------------
# Android App Configuration Targets
# -----------------------------------------------------------------------------
SHELL := /bin/bash

.PHONY: _android_app_configuration


# ------------------------------
# Targets
# ------------------------------

ifndef INCLUDED_ANDROID_KEYSTORE_CONFIGURATION_TARGETS
  include $(DEVOPS_TOOLKIT)/frontend/make/utils/android_keystore_configuration_targets.mk
endif

ifndef INCLUDED_GCP_CONFIGURATION_TARGETS
  include $(DEVOPS_TOOLKIT)/frontend/make/utils/gcp_configuration_targets.mk
endif

_android_app_configuration: _android_keystore_configuration _android_gcp_configuration
	@echo "[INFO] [Android App Configuration] All required Android environment variables have been exported."


INCLUDED_ANDROID_APP_CONFIGURATION_TARGETS := 1
