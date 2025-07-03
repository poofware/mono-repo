# -------------------------
# Root Makefile for "meta-service"
# -------------------------

SHELL := /bin/bash

# Connect devops-toolkit
REPO_ROOT      := $(shell git -C $(CURDIR) rev-parse --show-toplevel)
ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  include $(REPO_ROOT)/devops-toolkit/bootstrap.mk
endif


# ------------------------------
# Internal Variable Declaration
# ------------------------------ 

ENV ?= dev-test
COMPOSE_PROJECT_NAME := meta-service
COMPOSE_NETWORK_NAME := meta_network

COMPOSE_FILE := meta.compose.yaml

WITH_DEPS := 1

####################################################################
# Services
####################################################################
AUTH_SERVICE_NAME := auth-service
ACCOUNT_SERVICE_NAME := account-service
INTEREST_SERVICE_NAME := interest-service
JOBS_SERVICE_NAME := jobs-service
EARNINGS_SERVICE_NAME := earnings-service

DEPS := DEP_THE_WEBSITE:../../frontend/apps/the-website:"" \
		DEP_PM_APP:../../frontend/apps/pm-app:"" \
		DEP_AUTH_SERVICE:../services/$(AUTH_SERVICE_NAME):8082 \
		DEP_ACCOUNT_SERVICE:../services/$(ACCOUNT_SERVICE_NAME):8083 \
		DEP_INTEREST_SERVICE:../services/$(INTEREST_SERVICE_NAME):8084 \
		DEP_JOBS_SERVICE:../services/$(JOBS_SERVICE_NAME):8085 \
		DEP_EARNINGS_SERVICE:../services/$(EARNINGS_SERVICE_NAME):8086

export SERVICES := $(AUTH_SERVICE_NAME) \
	$(ACCOUNT_SERVICE_NAME) \
	$(INTEREST_SERVICE_NAME) \
	$(JOBS_SERVICE_NAME) \
	$(EARNINGS_SERVICE_NAME)
####################################################################

ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose_project_configuration.mk
endif

export APP_NAME := meta-service
export APP_PORT := 8080
APP_IS_GATEWAY := 1
ENABLE_NGROK_FOR_DEV := 1
STAGING_FLY_TOML_PATH := deploy/staging.fly.toml
FLY_TOML_PATH := deploy/fly.toml
ifndef INCLUDED_APP_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/app/compose_app_configuration.mk
endif

# We exporting the host port so the deps don't compute their own...just use the gateways
DEPS_PASSTHROUGH_VARS += APP_HOST_PORT

DEPS_PASSTHROUGH_VARS += EXCLUDE_COMPOSE_PROFILE_APP
DEPS_PASSTHROUGH_VARS += EXCLUDE_COMPOSE_PROFILE_APP_POST_CHECK

# --------------------------------
# Targets
# --------------------------------

Dockerfile.generated: generate_Dockerfile.sh Makefile
	@echo "[INFO] [Generate Dockerfile] Dynamically generating Dockerfile for 'meta-service' image..."
	@./generate_Dockerfile.sh > Dockerfile.generated
	@echo "[INFO] [Generate Dockerfile] Dockerfile for 'meta-service' image generated successfully."

build:: Dockerfile.generated

_deps-%: EXCLUDE_COMPOSE_PROFILE_APP := 1
_deps-%: EXCLUDE_COMPOSE_PROFILE_APP_POST_CHECK := 1
_deps-%::
	@echo "[INFO] [Export Exclude Profiles] Exporting exclude profiles for 'meta-service'..."

ifndef INCLUDED_COMPOSE_APP_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/app/compose_app_targets.mk
endif

up:: _deps-_up-app-post-check

