# ----------------------
# Compose Up Target
# ----------------------

SHELL := /bin/bash

.PHONY: up _up-db migrate _unlocked_migrate _up-app-pre _up-app-post-check

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
# Internal Variable Declaration
# --------------------------

# Define a shared lock file for all migration processes.
# This ensures that even in parallel runs, only one `migrate` can execute at a time.
MIGRATION_LOCK_FILE ?= /tmp/meta-service-migrations.lock


# --------------------------
# Targets
# --------------------------

ifndef INCLUDED_COMPOSE_BUILD
  include $(DEVOPS_TOOLKIT)/backend/make/compose/compose_project_targets/compose_build.mk
endif

ifndef INCLUDED_COMPOSE_DEPS_UP
  include $(DEVOPS_TOOLKIT)/backend/make/compose/compose_project_targets/compose_deps_targets/compose_deps_up.mk
endif

_up-db:
	@if [ -z "$(COMPOSE_PROFILE_DB_SERVICES)" ]; then \
		echo "[WARN] [Up-DB] No services found matching the '$(COMPOSE_PROFILE_DB)' profile. Skipping..."; \
	else \
		echo "[INFO] [Up-DB] Starting any database services found matching the '$(COMPOSE_PROFILE_DB)' profile..."; \
		echo "[INFO] [Up-DB] Found services: $(COMPOSE_PROFILE_DB_SERVICES)"; \
		$(COMPOSE_CMD) --profile $(COMPOSE_PROFILE_DB) up -d && echo "[INFO] [Up-DB] Done. Any '$(COMPOSE_PROFILE_DB)' services found are up and running." || \
			echo "[WARN] [Up-DB] '$(COMPOSE_CMD) --profile $(COMPOSE_PROFILE_DB) up -d' failed (most likely already running). Ignoring..."; \
	fi

## Starts any migration services found matching the 'migrate' profile (MIGRATE_MODE=backward|forward to specify the migration mode, backward for reversing migrations, forward for running migrations, ENV determines the behavior of the target)
migrate:: _up-network
	@echo "[INFO] [Migrate] Acquiring lock for migrations: $(MIGRATION_LOCK_FILE)..."
	@# Use flock to ensure only one process runs the migration at a time.
	@# It will wait for the lock file to be released before proceeding.
	@# We pass down MIGRATE_MODE to the inner make command to preserve its value.
	@flock $(MIGRATION_LOCK_FILE) -c '$(MAKE) --no-print-directory _unlocked_migrate MIGRATE_MODE=$(MIGRATE_MODE)'
	@echo "[INFO] [Migrate] Lock released."

# This is the new internal target containing the original migration logic.
# It is only ever called by the locked `migrate` target above.
_unlocked_migrate:
	@echo "[INFO] [Migrate] Lock acquired. Proceeding with migration..."
	@if [ -z "$(COMPOSE_PROFILE_MIGRATE_SERVICES)" ]; then \
		echo "[WARN] [Up-Migrate] No services found matching the '$(COMPOSE_PROFILE_MIGRATE)' profile. Skipping..."; \
	else \
		echo "[INFO] [Up-Migrate] Starting any migration services found matching the '$(COMPOSE_PROFILE_MIGRATE)' profile..."; \
		echo "[INFO] [Up-Migrate] Found services: $(COMPOSE_PROFILE_MIGRATE_SERVICES)"; \
		$(COMPOSE_CMD) --profile $(COMPOSE_PROFILE_MIGRATE) up --no-build; \
		echo "[INFO] [Up-Migrate] Done. Any '$(COMPOSE_PROFILE_MIGRATE)' services found were run."; \
		$(MAKE) _check-failed-services --no-print-directory PROFILE_TO_CHECK=$(COMPOSE_PROFILE_MIGRATE) SERVICES_TO_CHECK="$(COMPOSE_PROFILE_MIGRATE_SERVICES)"; \
	fi

_up-app-pre:
	@if [ -z "$(COMPOSE_PROFILE_APP_PRE_SERVICES)" ]; then \
		echo "[WARN] [Up-App-Pre] No services found matching the '$(COMPOSE_PROFILE_APP_PRE)' profile. Skipping..."; \
	else \
		echo "[INFO] [Up-App-Pre] Starting any app pre-start services found matching the '$(COMPOSE_PROFILE_APP_PRE)' profile..."; \
		echo "[INFO] [Up-App-Pre] Found services: $(COMPOSE_PROFILE_APP_PRE_SERVICES)"; \
		$(COMPOSE_CMD) --profile $(COMPOSE_PROFILE_APP_PRE) up -d --no-build; \
		echo "[INFO] [Up-App-Pre] Done. Any '$(COMPOSE_PROFILE_APP_PRE)' services found are up and running."; \
	fi

_up-app-post-check:
	@if [ -z "$(COMPOSE_PROFILE_APP_POST_CHECK_SERVICES)" ]; then \
		echo "[WARN] [Up-App-Post-Check] No services found matching the '$(COMPOSE_PROFILE_APP_POST_CHECK)' profile. Skipping..."; \
	else \
		echo "[INFO] [Up-App-Post-Check] Starting any app post-start check services found matching the '$(COMPOSE_PROFILE_APP_POST_CHECK)' profile..."; \
		echo "[INFO] [Up-App-Post-Check] Found services: $(COMPOSE_PROFILE_APP_POST_CHECK_SERVICES)"; \
		$(COMPOSE_CMD) --profile $(COMPOSE_PROFILE_APP_POST_CHECK) up --no-build; \
		echo "[INFO] [Up-App-Post-Check] Done. Any '$(COMPOSE_PROFILE_APP_POST_CHECK)' services found were run."; \
		$(MAKE) _check-failed-services --no-print-directory PROFILE_TO_CHECK=$(COMPOSE_PROFILE_APP_POST_CHECK) SERVICES_TO_CHECK="$(COMPOSE_PROFILE_APP_POST_CHECK_SERVICES)"; \
	fi

_up-app:
	@if [ -z "$(COMPOSE_PROFILE_APP_SERVICES)" ]; then \
		echo "[ERROR] [Up-App] No services found matching the '$(COMPOSE_PROFILE_APP)' profile!"; \
	else \
		echo "[INFO] [Up-App] Starting app services found matching the '$(COMPOSE_PROFILE_APP)' profile..."; \
		echo "[INFO] [Up-App] Found services: $(COMPOSE_PROFILE_APP_SERVICES)"; \
		echo "[INFO] [Up-App] Spinning up app..."; \
		$(COMPOSE_CMD) --profile $(COMPOSE_PROFILE_APP) up -d --no-build; \
		echo "[INFO] [Up-App] Done. $$APP_NAME is running on $$APP_URL_FROM_ANYWHERE"; \
	fi

_up-network:
	@echo "[INFO] [Up-Network] Creating network '$(COMPOSE_NETWORK_NAME)'..."
	@docker network create --ipv6 $(COMPOSE_NETWORK_NAME) && \
		echo "[INFO] [Up-Network] Network '$(COMPOSE_NETWORK_NAME)' successfully created." || \
		echo "[WARN] [Up-Network] 'docker network create $(COMPOSE_NETWORK_NAME)' failed (network most likely already exists). Ignoring..."

_up:
	@echo "[INFO] [Up] Calling 'build' target..."
	@$(MAKE) build --no-print-directory WITH_DEPS=0

	@$(MAKE) _up-network --no-print-directory

ifneq (,$(filter $(ENV),$(DEV_TEST_ENV) $(DEV_ENV)))
	@$(MAKE) _up-db --no-print-directory
endif

	@$(MAKE) migrate --no-print-directory

	@$(MAKE) _up-app-pre --no-print-directory

	@if [ "$(EXCLUDE_COMPOSE_PROFILE_APP)" -eq 1 ]; then \
		echo "[INFO] [Up] Skipping app startup... EXCLUDE_COMPOSE_PROFILE_APP is set to 1"; \
	else \
		$(MAKE) _up-app --no-print-directory; \
	fi

	@if [ "$(EXCLUDE_COMPOSE_PROFILE_APP_POST_CHECK)" -eq 1 ]; then \
	  echo "[INFO] [Up] Skipping app post-check... EXCLUDE_COMPOSE_PROFILE_APP_POST_CHECK is set to 1"; \
	else \
	  $(MAKE) _up-app-post-check --no-print-directory; \
	fi

## Starts services for all compose profiles in order (EXCLUDE_COMPOSE_PROFILE_APP=1 to exclude profile 'app' from 'up' - EXCLUDE_COMPOSE_PROFILE_APP_POST_CHECK=1 to exclude profile 'app_post_check' from 'up' - WITH_DEPS=1 to 'up' dependency projects as well)
up::
	@$(MAKE) _up --no-print-directory


INCLUDED_COMPOSE_UP := 1

