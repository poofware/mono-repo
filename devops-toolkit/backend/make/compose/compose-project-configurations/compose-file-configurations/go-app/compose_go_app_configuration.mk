# ------------------------------
# Compose Go App Configuration
# ------------------------------

SHELL := /bin/bash

# Check that the current working directory is the root of a Go service by verifying that go.mod exists.
ifeq ($(wildcard go.mod),)
  $(error Error: go.mod not found. Please ensure you are in the root directory of your Go service.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  $(error [ERROR] [Compose Go App Configuration] The Compose Project Configuration must be included before any compose file configuration. \
	Include $$(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose_project_configuration.mk in your root Makefile.)
endif

ifdef INCLUDED_COMPOSE_APP_CONFIGURATION
  $(error [ERROR] [Compose Go App Configuration] The Compose App Configuration must not be included before this file. \
	This file includes the Compose App Configuration, which is required for the Compose Go App Configuration.)
endif


# --------------------------------
# External Variable Validation
# --------------------------------

# Root Makefile variables #

ifneq ($(origin PACKAGES), file)
  $(error PACKAGES is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
	Define it empty if your app has no dependency packages. \
    Example: PACKAGES="go-middleware go-repositories go-compose go-models" or PACKAGES="")
endif


# ------------------------------
# Internal Variable Declarations
# ------------------------------

export GO_VERSION := 1.24
export PACKAGES

ifndef INCLUDED_COMPOSE_APP_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/app/compose_app_configuration.mk
endif



INCLUDED_COMPOSE_GO_APP_CONFIGURATION := 1
