# --------------------------
# App Secrets JSON
# -------------------------
SHELL := /bin/bash

.PHONY: _hcp_app_secrets_json

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif


# --------------------------------
# External Variable Validation
# --------------------------------

# Root Makefile variables #

ifneq ($(origin HCP_APP_NAME), file)
  $(error HCP_APP_NAME is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
    Example: HCP_APP_NAME="account-service")
endif

# --------------------------------
# Internal Variable Declaration
# --------------------------------


# --------------------------------
# Targets
# --------------------------------

_hcp_app_secrets_json:
ifndef INCLUDED_HCP_CONFIGURATION
	$(eval include $(DEVOPS_TOOLKIT_PATH)/shared/make/utils/hcp_configuration.mk)
endif
ifndef APP_SECRETS_JSON
	$(info [INFO] [App Secrets Json] Fetching App Secrets Json for HCP app $(HCP_APP_NAME)...)
	$(eval APP_SECRETS_JSON := $(shell $(DEVOPS_TOOLKIT_PATH)/shared/scripts/fetch_hcp_secret_from_secrets_json.sh))
	$(if $(APP_SECRETS_JSON),,$(error Failed to fetch HCP secrets))
	@echo "[INFO] [App Secrets Json] App Secrets Json set."
endif


INCLUDED_HCP_APP_SECRETS_JSON := 1
