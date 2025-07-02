# -----------------------
# ENV Configuration
# -----------------------

SHELL := /bin/bash

INCLUDED_ENV_CONFIGURATION := 1


# ---------------------------------
# Internal Variable Declaration
# ---------------------------------

ENV ?= dev-test

DEV_TEST_ENV := dev-test
DEV_ENV := dev
STAGING_TEST_ENV := staging-test
STAGING_ENV := staging
PROD_ENV := prod

ALLOWED_ENVS := $(DEV_TEST_ENV) $(DEV_ENV) $(STAGING_TEST_ENV) $(STAGING_ENV) $(PROD_ENV)


# --------------------------------
# External Variable Validation
# --------------------------------

# Root Makefile variables, possibly overridden by the environment #

ifndef ENV
  $(error ENV is not set. Please define it in your local Makefile or runtime/ci environment. \
  Example: ENV=dev-test, Options: $(ALLOWED_ENVS))
endif

ifeq (,$(filter $(ENV),$(ALLOWED_ENVS)))
  $(error ENV is set to an invalid value. Allowed values are: $(ALLOWED_ENVS))
endif


# ---------------------------------
# Internal Variable Declaration
# ---------------------------------

export ENV
