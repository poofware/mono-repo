# --------------------
# Compose Deps Targets
# --------------------

SHELL := /bin/bash

.PHONY: _deps-%

# Check that the current working directory is the root of a project by verifying that the root Makefile exists.  
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_COMPOSE_APP_CONFIGURATION
  $(error [ERROR] [Compose Deps Targets] The Compose App Configuration must be included before any Compose Deps Targets.)
endif

ifdef INCLUDED_COMPOSE_PROJECT_TARGETS
  $(error [ERROR] [Compose Deps Targets] The Compose Project Targets must not be included before this file.)
endif


# ----------------------------------
# Internal Variable Declaration
# ----------------------------------

# Controls parallel execution of dependency tasks.
# Set to 1 to run dependency tasks in parallel, which can significantly speed up `up` and `build` commands.
# Defaults to 0 (sequential execution) for predictable output and easier debugging.
# Example: make up PARA_DEPS=1
PARA_DEPS ?= 1


# ----------------------
# Targets
# ----------------------

# This pattern target runs the given make command (e.g., 'up', 'build') on all
# dependencies defined in the DEPS variable.
# Execution mode is controlled by the PARA_DEPS flag.
_deps-%::
	@if [ "$(WITH_DEPS)" -eq 1 ] && [ -n "$(DEPS)" ]; then \
		if [ "$(PARA_DEPS)" -eq 1 ]; then \
			echo "[INFO] [Deps-$*] Parallel execution enabled (PARA_DEPS=1)."; \
			echo "[INFO] [Deps-$*] Pre-flight check for dependency paths..."; \
			for dep in $(DEPS); do \
				dep_path=$$(echo $$dep | cut -d: -f2); \
				if [ ! -d "$$dep_path" ]; then \
					echo "[ERROR] [Deps-$*] Dependency path '$$dep_path' does not exist. Halting." >&2; \
					exit 1; \
				fi; \
			done; \
			echo "[INFO] [Deps-$*] All dependency paths are valid. Starting parallel execution..."; \
			\
			pids=""; \
			for dep in $(DEPS); do \
				( \
					set -e; \
					dep_path=$$(echo $$dep | cut -d: -f2); \
					dep_port=$$(echo $$dep | cut -d: -f3); \
					echo "[INFO] [Deps-$*] [$$dep_path] Running 'make $*' in background..."; \
					setsid env -i HOME="$(HOME)" TERM="$(TERM)" PATH="$(PATH)" MAKEFLAGS="$(MAKEFLAGS)" MAKELEVEL="$$(($(MAKELEVEL) + 1))" \
					    $(foreach var,$(DEPS_PASSTHROUGH_VARS),$(var)="$($(var))") \
					        $(MAKE) -C $$dep_path $* APP_PORT=$$dep_port </dev/null; \
				) & \
				pids="$$pids $$!"; \
			done; \
			\
			echo "[INFO] [Deps-$*] Waiting for all parallel dependency tasks to complete..."; \
			final_ret=0; \
			for pid in $$pids; do \
				if ! wait $$pid; then \
					echo "[ERROR] [Deps-$*] Dependency task with PID $$pid failed." >&2; \
					final_ret=1; \
				fi; \
			done; \
			\
			if [ $$final_ret -ne 0 ]; then \
				echo "[ERROR] [Deps-$*] One or more dependency tasks failed. Halting." >&2; \
				exit 1; \
			fi; \
			echo "[INFO] [Deps-$*] All dependency tasks completed successfully."; \
		else \
			echo "[INFO] [Deps-$*] Sequential execution enabled (default). Set PARA_DEPS=1 to run in parallel."; \
			for dep in $(DEPS); do \
				dep_path=$$(echo $$dep | cut -d: -f2); \
				dep_port=$$(echo $$dep | cut -d: -f3); \
				if [ ! -d "$$dep_path" ]; then \
					echo "[ERROR] [Deps-$*] Dependency '$$dep_path' found in DEPS does not exist."; \
					exit 1; \
				fi; \
				echo "[INFO] [Deps-$*] Running 'make $* -C $$dep_path' with passthrough vars and APP_PORT=$$dep_port..."; \
				env -i HOME="$(HOME)" TERM="$(TERM)" PATH="$(PATH)" MAKEFLAGS="$(MAKEFLAGS)" MAKELEVEL="$$(($(MAKELEVEL) + 1))" \
				$(foreach var,$(DEPS_PASSTHROUGH_VARS),$(var)="$($(var))") \
					$(MAKE) -C $$dep_path $* APP_PORT=$$dep_port || exit $$?; \
			done; \
		fi; \
	else \
		if [ "$(WITH_DEPS)" -eq 1 ]; then \
			echo "[INFO] [Deps-$*] No dependencies defined in DEPS variable. Skipping."; \
		fi; \
	fi

ifndef INCLUDED_COMPOSE_DEPS_CLEAN
  include devops-toolkit/backend/make/compose/compose-project-targets/compose-deps-targets/compose_deps_clean.mk
endif
ifndef INCLUDED_COMPOSE_DEPS_BUILD
  include devops-toolkit/backend/make/compose/compose-project-targets/compose-deps-targets/compose_deps_build.mk
endif
ifndef INCLUDED_COMPOSE_DEPS_UP
  include devops-toolkit/backend/make/compose/compose-project-targets/compose-deps-targets/compose_deps_up.mk
endif
ifndef INCLUDED_COMPOSE_DEPS_DOWN
  include devops-toolkit/backend/make/compose/compose-project-targets/compose-deps-targets/compose_deps_down.mk
endif


INCLUDED_COMPOSE_DEPS_TARGETS := 1
