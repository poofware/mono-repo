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
APP_NAME := admin-app

BACKEND_GATEWAY_PATH ?= ../meta-service

include $(DEVOPS_TOOLKIT_PATH)/frontend/make/web_flutter_app.mk

