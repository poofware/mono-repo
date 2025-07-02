# ------------------------------
# Compose Go App Targets
# ------------------------------

SHELL := /bin/bash

.PHONY: help build

# Check that the current working directory is the root of a Go service by verifying that go.mod exists.
ifeq ($(wildcard go.mod),)
  $(error Error: go.mod not found. Please ensure you are in the root directory of your Go service.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

ifndef INCLUDED_COMPOSE_GO_APP_CONFIGURATION
  $(error [ERROR] [Compose Go App Targets] The Compose Go App Configuration must be included before any Compose Go App Targets.)
endif

ifdef INCLUDED_APP_TARGETS
  $(error [ERROR] [Compose Go App Configuration] The Compose App Targets must not be included before this file. \
	This file includes the Compose App Targets, which are required for the Compose Go App Targets.)
endif


# --------------------------------
# Targets
# --------------------------------

ifndef INCLUDED_GO_APP_UPDATE
  include $(DEVOPS_TOOLKIT)/backend/make/utils/go_app_update.mk
endif
ifndef INCLUDED_VENDOR
  include $(DEVOPS_TOOLKIT)/backend/make/utils/vendor.mk
endif

build:: vendor

ifndef INCLUDED_COMPOSE_APP_TARGETS
  include $(DEVOPS_TOOLKIT)/backend/make/compose/compose-project-configurations/compose-file-configurations/app/compose_app_targets.mk
endif

help::
	@echo "--------------------------------------------------"
	@echo "[INFO] Go App Configuration variables:"
	@echo "--------------------------------------------------"
	@echo "APP_NAME: $(APP_NAME)"
	@echo "APP_PORT: $(APP_PORT)"
	@echo "LOG_LEVEL: $(LOG_LEVEL)"
	@echo "PACKAGES: $(PACKAGES)"
	@echo "APP_URL_FROM_COMPOSE_NETWORK: $(APP_URL_FROM_COMPOSE_NETWORK)"
	@echo "APP_URL_FROM_ANYWHERE: $(APP_URL_FROM_ANYWHERE)"
	@echo "--------------------------------------------------"
	@echo


INCLUDED_COMPOSE_GO_APP_TARGETS := 1
