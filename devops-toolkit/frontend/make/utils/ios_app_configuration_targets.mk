# -----------------------------------------------------------------------------
# iOS App Configuration Targets
# -----------------------------------------------------------------------------
SHELL := /bin/bash

.PHONY: _ios_app_configuration

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif


# ------------------------------
# Targets
# ------------------------------

ifndef INCLUDED_GCP_CONFIGURATION_TARGETS
  include $(DEVOPS_TOOLKIT)/frontend/make/utils/gcp_configuration_targets.mk
endif

_ios_app_configuration: _ios_gcp_configuration
	@echo "[INFO] [Android App Configuration] All required Android environment variables have been exported."


INCLUDED_IOS_APP_CONFIGURATION_TARGETS := 1
