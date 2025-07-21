# ------------------------------
# Compose Project Help Target
# ------------------------------

SHELL := /bin/bash

# Check that the current working directory is the root of a project by verifying that the Makefile exists. 
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

ifndef INCLUDED_HELP
  include $(DEVOPS_TOOLKIT_PATH)/shared/make/help.mk
endif

help::
	@echo "--------------------------------------------------"
	@echo "[INFO] Compose Project Configuration variables:"
	@echo "--------------------------------------------------"
	@echo "COMPOSE_NETWORK_NAME: $(COMPOSE_NETWORK_NAME)"
	@echo "ENV: $(ENV)"
	@echo "UNIQUE_RUN_NUMBER: $(UNIQUE_RUN_NUMBER)"
	@echo "UNIQUE_RUNNER_ID: $(UNIQUE_RUNNER_ID)"
	@echo "WITH_DEPS: $(WITH_DEPS)"
	@echo "DEPS: $(DEPS)"
	@echo "COMPOSE_FILE: $(COMPOSE_FILE)"
	@echo "BWS_CLIENT_ID": xxxxxxxx
	@echo "BWS_CLIENT_SECRET": xxxxxxxx
	@echo "BWS_ACCESS_TOKEN": xxxxxxxx
	@echo "--------------------------------------------------"
	@echo
	@echo "--------------------------------------------------"
	@echo "[INFO] Effective compose services for each profile:"
	@echo "--------------------------------------------------"
	@echo "$(COMPOSE_PROFILE_APP)                  : $(COMPOSE_PROFILE_APP_SERVICES)"
	@echo "$(COMPOSE_PROFILE_DB)                   : $(COMPOSE_PROFILE_DB_SERVICES)"
	@echo "$(COMPOSE_PROFILE_MIGRATE)              : $(COMPOSE_PROFILE_MIGRATE_SERVICES)"
	@echo "$(COMPOSE_PROFILE_APP_PRE)              : $(COMPOSE_PROFILE_APP_PRE_SERVICES)"
	@echo "$(COMPOSE_PROFILE_APP_POST_CHECK)       : $(COMPOSE_PROFILE_APP_POST_CHECK_SERVICES)"
	@echo "$(COMPOSE_PROFILE_APP_INTEGRATION_TEST) : $(COMPOSE_PROFILE_APP_INTEGRATION_TEST_SERVICES)"
	@echo "$(COMPOSE_PROFILE_APP_UNIT_TEST)        : $(COMPOSE_PROFILE_APP_UNIT_TEST_SERVICES)"
	@echo "--------------------------------------------------"
	@echo "[INFO] For information on available profiles, reference $(DEVOPS_TOOLKIT_PATH)/README.md"
	@echo



INCLUDED_COMPOSE_PROJECT_HELP := 1
