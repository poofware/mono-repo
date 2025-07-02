# -----------------------
# Compose CI Target
# -----------------------

SHELL := /bin/bash

.PHONY: ci

# Check that the current working directory is the root of a project by verifying that the root Makefile exists.
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

ifndef INCLUDED_COMPOSE_UP
  include $(DEVOPS_TOOLKIT)/backend/make/go-app/go_app_up.mk
endif
ifndef INCLUDED_COMPOSE_TEST
  include $(DEVOPS_TOOLKIT)/backend/make/go-app/go_app_test.mk
endif
ifndef INCLUDED_COMPOSE_DOWN
  include $(DEVOPS_TOOLKIT)/backend/make/go-app/go_app_down.mk
endif


## CI pipeline: Starts services, runs both integration and unit tests, and then shuts down all containers
ci::
	@echo "[INFO] [CI] Starting pipeline..."
	@echo "[INFO] [CI] Calling 'down' target to ensure a clean state..."
	@$(MAKE) down --no-print-directory
	@echo "[INFO] [CI] Calling 'up' target..."
	@$(MAKE) up --no-print-directory
	@echo "[INFO] [CI] Calling 'integration-test' target..."
	@$(MAKE) integration-test --no-print-directory
	@# $(MAKE) unit-test  # TODO: implement unit tests
	@echo "[INFO] [CI] Calling 'down' target..."
	@$(MAKE) down --no-print-directory
	@echo "[INFO] [CI] Pipeline complete."


INCLUDED_COMPOSE_CI := 1
