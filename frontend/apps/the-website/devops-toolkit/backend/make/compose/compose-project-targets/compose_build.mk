# ----------------------
# Compose Build Target
# ----------------------

SHELL := /bin/bash

.PHONY: build

# Check that the current working directory is the root of a project by verifying that the root Makefile exists.
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_COMPOSE_APP_CONFIGURATION
  $(error [ERROR] [Compose App Configuration] The Compose App Configuration must be included before any Compose Project Targets.)
endif


# -------------------------------- 
# Internal Variable Declaration
# --------------------------------

SSH_DOCKER_BUILD_CMD := devops-toolkit/backend/scripts/ssh_docker_build.sh compose \
						--project-directory $(COMPOSE_PROJECT_DIR) \
						-p $(COMPOSE_PROJECT_NAME)


# --------------------------
# Targets
# --------------------------

ifndef INCLUDED_COMPOSE_DEPS_BUILD
  include devops-toolkit/backend/make/compose/compose_project_targets/compose_deps_targets/compose_deps_build.mk
endif

## Builds services for all specified services (COMPOSE_BUILD_SERVICES must be set to a list of services to build - COMPOSE_BUILD_BASE_SERVICES for building base images is optional)
build::
	@if [ -n "$$(echo '$(COMPOSE_BUILD_BASE_SERVICES)' | xargs)" ]; then \
		echo "[INFO] [Build] Building Docker images for base services: $(COMPOSE_BUILD_BASE_SERVICES)..."; \
		$(SSH_DOCKER_BUILD_CMD) build $(COMPOSE_BUILD_BASE_SERVICES); \
	fi

	@if [ -n "$$(echo '$(COMPOSE_BUILD_SERVICES)' | xargs)" ]; then \
		echo "[INFO] [Build] Building Docker images for services: $(COMPOSE_BUILD_SERVICES)..."; \
		$(SSH_DOCKER_BUILD_CMD) build $(COMPOSE_BUILD_SERVICES); \
	else \
		echo "[ERROR] [Build] No services found to build. Please set COMPOSE_BUILD_SERVICES to a list of services to build."; \
		exit 1; \
	fi

	@echo "[INFO] [Build] Done."


INCLUDED_COMPOSE_BUILD := 1
