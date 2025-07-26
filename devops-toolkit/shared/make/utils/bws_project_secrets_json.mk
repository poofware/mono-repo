# --------------------------
# BWS Secrets JSON
# -------------------------
SHELL := /bin/bash

.PHONY: _bws_project_secrets_json

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif


# --------------------------------
# External Variable Validation
# --------------------------------

# Root Makefile variables #

ifneq ($(origin BWS_PROJECT_NAME), file)
  $(error BWS_PROJECT_NAME is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
    Example: BWS_PROJECT_NAME="account-service")
endif

# --------------------------------
# Internal Variable Declaration
# --------------------------------


# --------------------------------
# Targets
# --------------------------------

_bws_project_secrets_json:
ifndef PROJECT_SECRETS_JSON
	$(info [INFO] [BWS Project Secrets Json] Fetching BWS Project Secrets Json...)
	$(eval PROJECT_SECRETS_JSON := $(shell $(DEVOPS_TOOLKIT_PATH)/shared/scripts/fetch_bws_secret.sh))
	$(if $(PROJECT_SECRETS_JSON),,$(error Failed to fetch BWS secrets))
	@echo "[INFO] [BWS Project Secrets Json] BWS Project Secrets Json set."
endif


INCLUDED_BWS_PROJECT_SECRETS_JSON := 1

