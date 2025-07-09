# -----------------------------
# Admin Flutter App Makefile
#
# Compose Project combined with Flutter App
# -----------------------------

SHELL := /bin/bash

# Connect devops-toolkit
REPO_ROOT      := $(shell git -C $(CURDIR) rev-parse --show-toplevel)
ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  include $(REPO_ROOT)/devops-toolkit/bootstrap.mk
endif
# ------------------------------
# Internal Variable Declaration
# ------------------------------

ENV ?= dev-test
COMPOSE_PROJECT_NAME := admin-app
COMPOSE_NETWORK_NAME ?= admin-app_network

COMPOSE_FILE := admin-app.compose.yaml

WITH_DEPS := 0
DEPS := ""

ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose_project_configuration.mk
endif

APP_NAME := $(COMPOSE_PROJECT_NAME)
override APP_PORT := 8080
STAGING_FLY_TOML_PATH := deploy/staging.fly.toml
FLY_TOML_PATH := deploy/fly.toml
ifndef INCLUDED_APP_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/app/compose_app_configuration.mk
endif


# ------------------------------
# Flutter App Configuration & Targets
# ------------------------------

BACKEND_GATEWAY_PATH ?= ../
FLUTTER_BASE_HREF := /admin/

include $(DEVOPS_TOOLKIT_PATH)/frontend/make/web_flutter_app.mk

# --------------------------------
# Compose Project Targets
# --------------------------------

build::
	@$(MAKE) build-web --no-print-directory

ifndef INCLUDED_COMPOSE_APP_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/app/compose_app_targets.mk
endif
