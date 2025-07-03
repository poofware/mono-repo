# -------------------------
# Root Makefile For Go App 'earnings-service'
# -------------------------

# Connect devops-toolkit
REPO_ROOT      := $(shell git -C $(CURDIR) rev-parse --show-toplevel)
ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  include $(REPO_ROOT)/devops-toolkit/bootstrap.mk
endif


# -------------------------
# External Compose Project Configuration
# -------------------------

ENV ?= dev-test

COMPOSE_PROJECT_NAME := earnings-service
COMPOSE_NETWORK_NAME ?= shared_service_network

WITH_DEPS ?= 0

# Key:Value pairs of dependency services, separated by a space.
# Format: DEP_<service_name>:<service_path>
DEPS := ""

DEPS_PASSTHROUGH_VARS := WITH_DEPS

COMPOSE_FILE := $(DEVOPS_TOOLKIT_PATH)/backend/docker/go-app.compose.yaml
COMPOSE_FILE := $(COMPOSE_FILE):$(DEVOPS_TOOLKIT_PATH)/backend/docker/db.compose.yaml
COMPOSE_FILE := $(COMPOSE_FILE):$(DEVOPS_TOOLKIT_PATH)/backend/docker/stripe.compose.yaml
COMPOSE_FILE := $(COMPOSE_FILE):override.compose.yaml

ifndef INCLUDED_COMPOSE_PROJECT_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose_project_configuration.mk
endif

# -------------------------
# Compose File Configurations
# -------------------------

# go-app.compose.yaml configurations 
export APP_NAME := $(COMPOSE_PROJECT_NAME)
export APP_PORT ?= 8080
export SHARED_PATH := $(REPO_ROOT)/backend/shared
PACKAGES := go-middleware go-repositories go-utils go-models go-dtos go-testhelpers
ENABLE_NGROK_FOR_DEV := 1
STAGING_FLY_TOML_PATH := deploy/staging.fly.toml
FLY_TOML_PATH := deploy/fly.toml
ifndef INCLUDED_COMPOSE_GO_APP_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/go-app/compose_go_app_configuration.mk
endif

# db.compose.yaml configurations
export COMPOSE_DB_NAME := shared_pg_db
export MIGRATIONS_PATH := $(REPO_ROOT)/backend/migrations
export HCP_APP_NAME_FOR_DB_SECRETS := $(APP_NAME)-$(ENV)

# stripe.compose.yaml configurations
export STRIPE_WEBHOOK_CONNECTED_EVENTS := account.updated,capability.updated,payout.paid,payout.failed,payment_intent.created
export STRIPE_WEBHOOK_PLATFORM_EVENTS := balance.available,transfer.reversed
export STRIPE_WEBHOOK_ROUTE := /api/v1/earnings/stripe/webhook
export STRIPE_WEBHOOK_CHECK_ROUTE := /api/v1/earnings/stripe/webhook/check

# -------------------------
# Final Compose Project Configuration and Targets
# -------------------------

ifndef INCLUDED_COMPOSE_GO_APP_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-configurations/compose-file-configurations/go-app/compose_go_app_targets.mk
endif

ifndef INCLUDED_COMPOSE_PROJECT_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-targets/compose_project_targets.mk
endif


