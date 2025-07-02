# ----------------------
# Compose Clean Target
# ----------------------

SHELL := /bin/bash

.PHONY: clean

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

# Check that the current working directory is the root of a project by verifying that the root Makefile exists.
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_COMPOSE_APP_CONFIGURATION
  $(error [ERROR] [Compose App Configuration] The Compose App Configuration must be included before any Compose Project Targets.)
endif


# --------------------------
# Targets
# --------------------------

ifndef INCLUDED_COMPOSE_DOWN
  include $(DEVOPS_TOOLKIT)/backend/make/compose/compose_project_targets/compose_down.mk
endif

ifndef INCLUDED_COMPOSE_DEPS_CLEAN
  include $(DEVOPS_TOOLKIT)/backend/make/compose/compose_project_targets/compose_deps_targets/compose_deps_clean.mk
endif

## Cleans everything (containers, images, volumes) (WITH_DEPS=1 to 'clean' dependency projects as well)
clean::
	@echo "[INFO] [Clean] Running down target..."
	@$(MAKE) down --no-print-directory WITH_DEPS=0
	@echo "[INFO] [Clean] Full nuke of containers, images, volumes, networks..."
	@$(COMPOSE_CMD) $(COMPOSE_PROFILE_FLAGS_DOWN_BUILD) down --rmi local -v --remove-orphans
	@echo "[INFO] [Clean] Done."


INCLUDED_COMPOSE_CLEAN := 1
