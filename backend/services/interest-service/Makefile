# -------------------------
# Root Makefile for "interest-service"
# -------------------------

# Connect devops-toolkit
REPO_ROOT      := $(shell git -C $(CURDIR) rev-parse --show-toplevel)
ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  include $(REPO_ROOT)/devops-toolkit/bootstrap.mk
endif


# 1) Basic Service Settings
ENV ?= dev-test
COMPOSE_PROJECT_NAME := interest-service
COMPOSE_NETWORK_NAME ?= shared_service_network

# Key:Value pairs of dependency services, separated by a space.
# Format: DEP_<service_name>:<service_path>
WITH_DEPS ?= 0
DEPS := ""

DEPS_PASSTHROUGH_VARS := WITH_DEPS

COMPOSE_FILE := $(DEVOPS_TOOLKIT_PATH)/backend/docker/go-app.compose.yaml
COMPOSE_FILE := $(COMPOSE_FILE):override.compose.yaml

# 2) Include the Compose Project Configuration
ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose_project_configuration.mk
endif

# 3) Go App Compose Configuration
export APP_NAME := $(COMPOSE_PROJECT_NAME)
export APP_PORT ?= 8080
export SHARED_PATH := $(REPO_ROOT)/backend/shared
PACKAGES := go-utils
STAGING_FLY_TOML_PATH := deploy/staging.fly.toml
PROD_FLY_TOML_PATH := deploy/fly.toml
ifndef INCLUDED_COMPOSE_GO_APP_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/go-app/compose_go_app_configuration.mk
endif

# 4) Go App Targets (build, test, update, etc.)
ifndef INCLUDED_COMPOSE_GO_APP_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/go-app/compose_go_app_targets.mk
endif

# 5) Finally, bring in the standard Compose project targets
ifndef INCLUDED_COMPOSE_PROJECT_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-targets/compose_project_targets.mk
endif


