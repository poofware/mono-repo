# ----------------------
# Compose Build Target
# ----------------------

SHELL := /bin/bash

.PHONY: build

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


# --------------------------------
# Internal Variable Declaration
# --------------------------------

SSH_DOCKER_BUILD_CMD := $(DEVOPS_TOOLKIT_PATH)/backend/scripts/ssh_docker_build.sh compose \
						--project-directory $(COMPOSE_PROJECT_DIR) \
						-p $(COMPOSE_PROJECT_NAME)

# ─────────────────────────────────────────────────────────────────────────────
# Helper sets for conditional platform builds
# ─────────────────────────────────────────────────────────────────────────────
APP_PROFILE_SERVICES        = $(COMPOSE_PROFILE_APP_SERVICES)
NON_APP_SERVICES            = $(filter-out $(APP_PROFILE_SERVICES),$(COMPOSE_BUILD_SERVICES))

BASE_APP_SERVICES           = $(COMPOSE_PROFILE_BASE_APP_SERVICES)
NON_BASE_APP_BASE_SERVICES  = $(filter-out $(BASE_APP_SERVICES),$(COMPOSE_BUILD_BASE_SERVICES))


# --------------------------
# Targets
# --------------------------

ifndef INCLUDED_COMPOSE_DEPS_BUILD
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose_project_targets/compose-deps-targets/compose_deps_build.mk
endif

## Builds services for all specified services (COMPOSE_BUILD_SERVICES must be set to a list of services to build - COMPOSE_BUILD_BASE_SERVICES for building base images is optional)
build::
	@echo "[INFO] [Build] ENV=$(ENV)"

ifeq ($(filter $(ENV),$(STAGING_ENV) $(STAGING_TEST_ENV)),)
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
else
	@if [ -n "$$(echo '$(NON_BASE_APP_BASE_SERVICES)' | xargs)" ]; then \
		echo "[INFO] [Build] Building Docker images for non-base_app base services: $(NON_BASE_APP_BASE_SERVICES)..."; \
		$(SSH_DOCKER_BUILD_CMD) build $(NON_BASE_APP_BASE_SERVICES); \
	fi

	@if [ -n "$$(echo '$(BASE_APP_SERVICES)' | xargs)" ]; then \
		echo "[INFO] [Build] Building Docker images for base_app services for linux/amd64: $(BASE_APP_SERVICES)..."; \
		export TARGET_PLATFORM=linux/amd64; \
		$(SSH_DOCKER_BUILD_CMD) build $(BASE_APP_SERVICES); \
	fi

	@if [ -n "$$(echo '$(NON_APP_SERVICES)' | xargs)" ]; then \
		echo "[INFO] [Build] Building Docker images for non-app services: $(NON_APP_SERVICES)..."; \
		$(SSH_DOCKER_BUILD_CMD) build $(NON_APP_SERVICES); \
	fi

	@if [ -n "$$(echo '$(APP_PROFILE_SERVICES)' | xargs)" ]; then \
		echo "[INFO] [Build] Building Docker images for app services for linux/amd64: $(APP_PROFILE_SERVICES)..."; \
		export TARGET_PLATFORM=linux/amd64; \
		$(SSH_DOCKER_BUILD_CMD) build $(APP_PROFILE_SERVICES); \
	fi
endif

	@echo "[INFO] [Build] Done."

INCLUDED_COMPOSE_BUILD := 1

