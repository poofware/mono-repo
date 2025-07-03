# ----------------------
# Compose Down Target
# ----------------------

SHELL := /bin/bash

.PHONY: down

# Check that the current working directory is the root of a project by verifying that the root Makefile exists.
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

ifndef INCLUDED_COMPOSE_APP_CONFIGURATION
  $(error [ERROR] [Compose App Configuration] The Compose App Configuration must be included before any Compose Project Targets.)
endif


# --------------------------
# Targets
# --------------------------

ifndef INCLUDED_COMPOSE_DEPS_DOWN
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose_project_targets/compose_deps_targets/compose_deps_down.mk
endif

_down-network:
	@echo "[INFO] [Down-Network] Removing network '$(COMPOSE_NETWORK_NAME)'..."
	@docker network rm $(COMPOSE_NETWORK_NAME) && echo "[INFO] [Down-Network] Network '$(COMPOSE_NETWORK_NAME)' successfully removed." || \
		echo "[WARN] [Down-Network] 'network rm $(COMPOSE_NETWORK_NAME)' failed (network most likely already removed or still being used) Ignoring..."


## Shuts down all containers (WITH_DEPS=1 to 'down' dependency projects as well)
down::
	@echo "[INFO] [Down] Removing containers & volumes, keeping images..."
	@$(COMPOSE_CMD) down -v --remove-orphans

	@$(MAKE) _down-network --no-print-directory

	@echo "[INFO] [Down] Done. Containers and volumes removed, images kept."


INCLUDED_COMPOSE_DOWN := 1
