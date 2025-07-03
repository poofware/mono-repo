# -----------------------------
# Worker Flutter App Makefile
# -----------------------------

SHELL := /bin/bash

# Connect devops-toolkit
REPO_ROOT      := $(shell git -C $(CURDIR) rev-parse --show-toplevel)
ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  include $(REPO_ROOT)/devops-toolkit/bootstrap.mk
endif


ENV ?= dev-test
APP_NAME := worker-app

BACKEND_GATEWAY_PATH ?= ../../../backend/meta-service

include $(DEVOPS_TOOLKIT_PATH)/frontend/make/mobile_flutter_app.mk
