# --------------------------
# App Secrets JSON
# -------------------------
SHELL := /bin/bash

.PHONY: _app_secrets_json

INCLUDED_APP_SECRETS_JSON := 1

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

_app_secrets_json:
ifndef INCLUDED_HCP_CONFIGURATION
	$(eval include devops-toolkit/shared/make/utils/hcp_configuration.mk)
endif
ifndef APP_SECRETS_JSON
	$(eval APP_SECRETS_JSON := $(shell devops-toolkit/shared/scripts/fetch_hcp_secret_from_secrets_json.sh))
	$(if $(APP_SECRETS_JSON),,$(error Failed to fetch HCP secrets))
	@echo "[INFO] [App Secrets Json] App Secrets Json set."
endif
