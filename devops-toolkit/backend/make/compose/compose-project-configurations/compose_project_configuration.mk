# ----------------------------------------------------
# Compose Project Configuration
# ----------------------------------------------------

SHELL := /bin/bash

# Check that the current working directory is the root of a project by verifying that the Makefile exists. 
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif


# --------------------------------
# External Variable Validation
# --------------------------------

# Runtime/Ci environment variables #

ifneq ($(origin UNIQUE_RUNNER_ID), environment)
  $(error UNIQUE_RUNNER_ID is either not set or set in the root Makefile. Please define it in your runtime/ci environment only. \
	Example: export UNIQUE_RUNNER_ID="john_snow")
endif

# Root Makefile variables, possibly overridden by the environment #

ifndef COMPOSE_NETWORK_NAME
  $(error COMPOSE_NETWORK_NAME is not set. Please define it in your local Makefile or runtime/ci environment. \
	Example: COMPOSE_NETWORK_NAME="shared_service_network")
endif

ifndef WITH_DEPS
  $(error WITH_DEPS is not set. Please define it in your local Makefile or runtime/ci environment. \
	Example: WITH_DEPS=1)
endif

# Root Makefile variables #

ifneq ($(origin COMPOSE_PROJECT_NAME), file)
  $(error COMPOSE_PROJECT_NAME is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
	Example: COMPOSE_PROJECT_NAME="account-service")
endif

ifneq ($(origin COMPOSE_FILE), file)
  $(error COMPOSE_FILE is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
	Should be a colon-separated list of additional compose files to include in the docker compose command. \
	Define it empty if no additional compose files are needed. \
	Example: COMPOSE_FILE="$(DEVOPS_TOOLKIT_PATH)/backend/docker/additional.compose.yaml:./override.compose.yaml" or COMPOSE_FILE="")
endif

ifneq ($(origin DEPS), file)
  $(error DEPS is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
	Define it empty if your app has no dependency apps. \
	Example: DEPS="/path/to/auth-service /path/to/account-service" or DEPS="")
endif

# ------------------------------
# Internal Variable Declaration
# ------------------------------ 

ifeq ($(WITH_DEPS),1)
  # Dynamically define DEP_* variables allowing overrides from environment
  ifneq ($(DEPS),"")
    $(foreach dep, $(DEPS), \
      $(eval dep_key := $(word 1, $(subst :, ,$(dep)))) \
      $(eval dep_val := $(word 2, $(subst :, ,$(dep)))) \
      $(eval dep_port := $(word 3, $(subst :, ,$(dep)))) \
      $(eval export $(dep_key) ?= $(dep_val)) \
    )

    # Rebuild DEPS preserving overridden values and non-overridable ports
    DEPS := $(foreach dep, $(DEPS), \
      $(word 1, $(subst :, ,$(dep))):$($(word 1, $(subst :, ,$(dep)))):$(word 3, $(subst :, ,$(dep))) \
    )
  endif
endif

export PRINT_INFO ?= 1

ifeq ($(PRINT_INFO),1)
  export PRINT_INFO := 0

  ifeq ($(WITH_DEPS),1)
    # Functions in make should always use '=', unless precomputing the value without dynamic args
    print-dep = $(info   $(1) = $($(1)), port = $(2))

    $(info --------------------------------------------------)
    $(info [INFO] WITH_DEPS is enabled. Effective dependency projects being used:)
    $(info --------------------------------------------------)
    # Print effective DEP_* values and ports
    ifneq ($(DEPS),"")
      $(foreach dep, $(DEPS), \
        $(call print-dep,$(word 1, $(subst :, ,$(dep))),$(word 3, $(subst :, ,$(dep)))) \
      )
    endif
    $(info )
    $(info --------------------------------------------------)
    $(info [INFO] To override paths, make with VAR=value (ports are not overridable))
    $(info )
  endif
endif

DEPS_PASSTHROUGH_VARS += COMPOSE_NETWORK_NAME
DEPS_PASSTHROUGH_VARS += BWS_ACCESS_TOKEN
DEPS_PASSTHROUGH_VARS += ENV
DEPS_PASSTHROUGH_VARS += UNIQUE_RUNNER_ID
DEPS_PASSTHROUGH_VARS += UNIQUE_RUN_NUMBER
DEPS_PASSTHROUGH_VARS += PRINT_INFO

ifndef INCLUDED_ENV_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/shared/make/utils/env_configuration.mk
endif

ifndef INCLUDED_LAUNCHDARKLY_CONSTANTS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/utils/launchdarkly_constants.mk
endif

UNFORMATTED_COMPOSE_FILE := $(COMPOSE_FILE)
export COMPOSE_FILE = $(shell echo "$(UNFORMATTED_COMPOSE_FILE)" | tr -d '[:space:]')
# For isolation of CI runs, and use of 3rd party services (e.g. Stripe)
UNIQUE_RUN_NUMBER ?= 0
UNFORMATTED_UNIQUE_RUN_NUMBER := $(UNIQUE_RUN_NUMBER)
export UNIQUE_RUN_NUMBER := $(subst _,-,$(UNFORMATTED_UNIQUE_RUN_NUMBER))
UNFORMATTED_UNIQUE_RUNNER_ID := $(UNIQUE_RUNNER_ID)
export UNIQUE_RUNNER_ID := $(subst _,-,$(UNFORMATTED_UNIQUE_RUNNER_ID))

export COMPOSE_NETWORK_NAME

COMPOSE_PROFILE_BASE_APP := base_app
COMPOSE_PROFILE_BASE_DB := base_db
COMPOSE_PROFILE_BASE_MIGRATE := base_migrate
COMPOSE_PROFILE_BASE_APP_INTEGRATION_TEST := base_app_integration_test

COMPOSE_PROFILE_APP := app
COMPOSE_PROFILE_DB := db
COMPOSE_PROFILE_MIGRATE := migrate
COMPOSE_PROFILE_APP_PRE := app_pre
COMPOSE_PROFILE_APP_POST_CHECK := app_post_check
COMPOSE_PROFILE_APP_INTEGRATION_TEST := app_integration_test
COMPOSE_PROFILE_APP_UNIT_TEST := app_unit_test

COMPOSE_PROJECT_DIR := ./

# Variable for app run/up/down docker compose commands
export COMPOSE_CMD := docker compose \
  --project-directory $(COMPOSE_PROJECT_DIR) \
  -p $(COMPOSE_PROJECT_NAME)

ifndef INCLUDE_COMPOSE_SERVICE_UTILS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/utils/compose_service_utils.mk
endif

COMPOSE_PROFILE_BASE_APP_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_BASE_APP))
COMPOSE_PROFILE_BASE_DB_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_BASE_DB))
COMPOSE_PROFILE_BASE_MIGRATE_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_BASE_MIGRATE))
COMPOSE_PROFILE_BASE_APP_INTEGRATION_TEST_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_BASE_APP_INTEGRATION_TEST))

COMPOSE_PROFILE_APP_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_APP))
COMPOSE_PROFILE_DB_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_DB))
COMPOSE_PROFILE_MIGRATE_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_MIGRATE))
COMPOSE_PROFILE_APP_PRE_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_APP_PRE))
COMPOSE_PROFILE_APP_POST_CHECK_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_APP_POST_CHECK))
COMPOSE_PROFILE_APP_INTEGRATION_TEST_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_APP_INTEGRATION_TEST))
COMPOSE_PROFILE_APP_UNIT_TEST_SERVICES = $(call get_profile_services,$(COMPOSE_PROFILE_APP_UNIT_TEST))

EXCLUDE_COMPOSE_PROFILE_APP ?= 0
EXCLUDE_COMPOSE_PROFILE_APP_POST_CHECK ?= 0

COMPOSE_BUILD_BASE_SERVICES = $(COMPOSE_PROFILE_BASE_APP_SERVICES) \
							  $(COMPOSE_PROFILE_BASE_DB_SERVICES) \
							  $(COMPOSE_PROFILE_BASE_MIGRATE_SERVICES)

COMPOSE_BUILD_SERVICES = $(COMPOSE_PROFILE_APP_SERVICES) \
						 $(COMPOSE_PROFILE_DB_SERVICES) \
						 $(COMPOSE_PROFILE_MIGRATE_SERVICES) \
						 $(COMPOSE_PROFILE_APP_PRE_SERVICES) \
						 $(COMPOSE_PROFILE_APP_POST_CHECK_SERVICES)


INCLUDED_COMPOSE_PROJECT_CONFIGURATION := 1
