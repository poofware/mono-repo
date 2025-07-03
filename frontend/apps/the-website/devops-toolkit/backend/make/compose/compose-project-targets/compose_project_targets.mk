# ------------------------------
# Compose Project Targets
# ------------------------------

SHELL := /bin/bash

# Check that the current working directory is the root of a project by verifying that the Makefile exists. 
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  $(error [ERROR] [Compose Project Targets] The Compose Project Configuration must be included before any Compose Project Targets.)
endif


# --------------------------------
# Targets
# --------------------------------

ifndef INCLUDED_COMPOSE_DEPS_TARGETS
  include devops-toolkit/backend/make/compose/compose-project-targets/compose-deps-targets/compose_deps_targets.mk
endif

ifndef INCLUDED_COMPOSE_DOWN
  include devops-toolkit/backend/make/compose/compose-project-targets/compose_down.mk
endif
ifndef INCLUDED_COMPOSE_BUILD
  include devops-toolkit/backend/make/compose/compose-project-targets/compose_build.mk
endif
ifndef INCLUDED_COMPOSE_UP
  include devops-toolkit/backend/make/compose/compose-project-targets/compose_up.mk
endif
ifndef INCLUDED_COMPOSE_TEST
  include devops-toolkit/backend/make/compose/compose-project-targets/compose_test.mk
endif
ifndef INCLUDED_COMPOSE_CLEAN
  include devops-toolkit/backend/make/compose/compose-project-targets/compose_clean.mk
endif
ifndef INCLUDED_COMPOSE_CI
  include devops-toolkit/backend/make/compose/compose-project-targets/compose_ci.mk
endif
ifndef INCLUDED_COMPOSE_PROJECT_HELP
  include devops-toolkit/backend/make/compose/compose-project-targets/compose_project_help.mk
endif


INCLUDED_COMPOSE_PROJECT_TARGETS := 1
