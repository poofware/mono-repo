# ------------------------------
# Compose App Configuration
# ------------------------------

SHELL := /bin/bash

# Check that the current working directory is the root of a project by verifying that the root Makefile exists.
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  $(error [ERROR] [App Compose Configuration] The Compose Project Configuration must be included before any compose file configuration. \
	Include $$(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose_project_configuration.mk in your root Makefile.)
endif


# --------------------------------
# External Variable Validation
# --------------------------------

# Root Makefile variables, possibly overridden by the environment #

ifndef APP_PORT
  $(error APP_PORT is not set. Please define it in your local Makefile or runtime/ci environment. \
	Example: APP_PORT=8080)
endif

# Root Makefile variables #

ifneq ($(origin APP_NAME), file)
  $(error APP_NAME is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
	Example: APP_NAME="account-service")
endif

# Optional override configuration env variables #

ifdef APP_URL_FROM_COMPOSE_NETWORK
  ifeq ($(origin APP_URL_FROM_COMPOSE_NETWORK), file)
    $(error APP_URL_FROM_COMPOSE_NETWORK override should be set as a runtime/ci environment variable, do not hardcode it in the root Makefile. \
	  Example: APP_URL_FROM_COMPOSE_NETWORK="http://meta-service:8080" make integration-test)
  endif
endif

ifdef APP_URL_FROM_ANYWHERE
  ifeq ($(origin APP_URL_FROM_ANYWHERE), file)
    $(error APP_URL_FROM_ANYWHERE override should be set as a runtime/ci environment variable, do not hardcode it in the root Makefile. \
	  Example: APP_URL_FROM_ANYWHERE="https://0.dev.fly.io" make integration-test)
  endif
endif

ifdef LOG_LEVEL
  ifeq ($(origin LOG_LEVEL), file)
    $(error LOG_LEVEL override should be set as a runtime/ci environment variable, do not hardcode it in the root Makefile. \
	  Example: LOG_LEVEL=debug make up)
  endif
endif


# ------------------------------
# Internal Variable Declaration
# ------------------------------

# For specific docker compose fields in our configuration
export APP_NAME
export APP_PORT

export LOG_LEVEL ?= info
export DEPS_PASSTHROUGH_VARS += LOG_LEVEL

ENABLE_NGROK_FOR_DEV ?= 0

ifeq ($(APP_IS_GATEWAY),1)
# If the app is a gateway to its dependencies, we need to passthrough some key network configurations to the deps targets.
# This ensures that the deps of the gateway app use the gateways addresses. This is important for obvious reasons.
DEPS_PASSTHROUGH_VARS += APP_URL_FROM_COMPOSE_NETWORK
DEPS_PASSTHROUGH_VARS += APP_URL_FROM_ANYWHERE
endif

ifneq (,$(filter $(ENV),$(DEV_TEST_ENV) $(DEV_ENV)))

  # If the app is a gateway, than always override a previously set APP_URL_FROM_COMPOSE_NETWORK
  ifndef APP_URL_FROM_COMPOSE_NETWORK
    export APP_URL_FROM_COMPOSE_NETWORK := http://$(APP_NAME):$(APP_PORT)
  else ifeq ($(APP_IS_GATEWAY),1)
    export APP_URL_FROM_COMPOSE_NETWORK := http://$(APP_NAME):$(APP_PORT)
  endif

  ifeq ($(ENABLE_NGROK_FOR_DEV),1)
    # Include ngrok as part of the project
    COMPOSE_FILE := $(COMPOSE_FILE):$(DEVOPS_TOOLKIT_PATH)/backend/docker/ngrok.compose.yaml
	
    ifndef INCLUDED_NGROK_AUTHTOKEN
      include $(DEVOPS_TOOLKIT_PATH)/backend/make/utils/ngrok_authtoken.mk
    endif

    DEPS_PASSTHROUGH_VARS += NGROK_AUTHTOKEN

    ifeq ($(APP_IS_GATEWAY),1)
      DEPS_PASSTHROUGH_VARS += NGROK_UP
    endif

    export NGROK_PORT := 4040
  endif

else

  ifndef INCLUDED_FLY_CONSTANTS
    include $(DEVOPS_TOOLKIT_PATH)/backend/make/utils/fly_constants.mk
  endif

  DEPS_PASSTHROUGH_VARS += FLY_API_TOKEN
  DEPS_PASSTHROUGH_VARS += FLY_WIREGUARD_UP

  ifneq (,$(filter $(ENV),$(STAGING_ENV) $(STAGING_TEST_ENV)))

    ifndef STAGING_FLY_TOML_PATH
      $(error STAGING_FLY_TOML_PATH is not set. Please define it in your local Makefile or runtime/ci environment. \
        Example: STAGING_FLY_TOML_PATH=staging.fly.toml)
    endif

    FLY_TOML_PATH := $(STAGING_FLY_TOML_PATH)
    FLY_ORG_NAME := $(FLY_STAGING_ORG_NAME)
    FLY_APP_NAME := $(subst _,-,$(APP_NAME)-$(UNIQUE_RUNNER_ID)-$(UNIQUE_RUN_NUMBER))
    FLY_URL := https://$(FLY_APP_NAME).fly.dev
    FLY_WIREGUARD_PEER_NAME := $(subst _,-,$(FLY_STAGING_ORG_NAME)-$(UNIQUE_RUNNER_ID)-$(UNIQUE_RUN_NUMBER))

    ifndef APP_URL_FROM_COMPOSE_NETWORK
      export APP_URL_FROM_COMPOSE_NETWORK := $(FLY_URL)
    endif
  
    ifndef APP_URL_FROM_ANYWHERE
      export APP_URL_FROM_ANYWHERE := $(FLY_URL)
    endif
  else ifneq (,$(filter $(ENV),$(PROD_ENV)))

    ifndef PROD_FLY_TOML_PATH
      $(error PROD_FLY_TOML_PATH is not set. Please define it in your local Makefile or runtime/ci environment. \
        Example: PROD_FLY_TOML_PATH=fly.toml)
    endif

    FLY_TOML_PATH := $(PROD_FLY_TOML_PATH)
    FLY_ORG_NAME := $(FLY_PROD_ORG_NAME)
    FLY_APP_NAME := $(subst _,-,$(APP_NAME)-$(UNIQUE_RUN_NUMBER))
    FLY_URL := https://$(FLY_APP_NAME).fly.dev
    FLY_WIREGUARD_PEER_NAME := $(subst _,-,$(FLY_ORG_NAME)-$(UNIQUE_RUNNER_ID)-$(UNIQUE_RUN_NUMBER))

    ifndef APP_URL_FROM_COMPOSE_NETWORK
      export APP_URL_FROM_COMPOSE_NETWORK := https://thepoofapp.com
    endif
  
    ifndef APP_URL_FROM_ANYWHERE
      export APP_URL_FROM_ANYWHERE := https://thepoofapp.com
    endif
  endif

endif


INCLUDED_COMPOSE_APP_CONFIGURATION := 1
