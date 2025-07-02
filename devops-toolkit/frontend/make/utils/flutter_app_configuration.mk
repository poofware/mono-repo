# --------------------------------
# Flutter App Configuration
# --------------------------------

SHELL := /bin/bash

# Check that the current working directory is the root of a Flutter app by verifying that pubspec.yaml exists.
ifeq ($(wildcard pubspec.yaml),)
  $(error Error: pubspec.yaml not found. Please ensure you are in the root directory of your Flutter app.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

# ------------------------------
# External Variable Validation
# ------------------------------

# Root Makefile variables #

ifneq ($(origin APP_NAME), file)
  $(error APP_NAME is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
	Example: APP_NAME="account-service")
endif

ifneq ($(origin BACKEND_GATEWAY_PATH), file)
  $(error BACKEND_GATEWAY_PATH is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
	Example: BACKEND_GATEWAY_PATH="../meta-service")
endif


# ------------------------------
# Internal Variable Declaration
# ------------------------------ 

ifndef INCLUDED_ENV_CONFIGURATION
  include $(DEVOPS_TOOLKIT)/shared/make/utils/env_configuration.mk
endif

LOG_LEVEL ?= info

export HCP_APP_NAME := $(APP_NAME)

VERBOSE ?= 0
VERBOSE_FLAG := $(if $(filter 1,$(VERBOSE)),--verbose,)

# -------------------------------------------------
# Macro: run_command_with_backend
#
# Runs a command with the backend up if AUTO_LAUNCH_BACKEND=1.
# Otherwise, runs the command directly.
# Note: This is provided so that frontend developers have as little backend friction
#       as possible. Full stack developers can turn this feature off by setting
#       AUTO_LAUNCH_BACKEND=0 with their make command.
# $(1) is the command to run.
# -------------------------------------------------
define run_command_with_backend
	if [ $(AUTO_LAUNCH_BACKEND) -eq 1 ]; then \
		echo "[INFO] [Auto Launch Backend] Auto launching backend..."; \
		echo "[INFO] [Auto Launch Backend] Calling 'up-backend' target..."; \
		$(MAKE) up-backend --no-print-directory; \
		$(1) || exit 1; \
	else \
		$(1); \
	fi
endef


INCLUDED_FLUTTER_APP_CONFIGURATION := 1
