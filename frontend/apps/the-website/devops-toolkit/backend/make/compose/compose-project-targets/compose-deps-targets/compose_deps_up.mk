# ------------------------------
# Compose Deps Up
# ------------------------------

SHELL := /bin/bash

ifndef INCLUDED_COMPOSE_APP_CONFIGURATION
  $(error [ERROR] [Compose App Configuration] The Compose App Configuration must be included before any Compose Deps Targets.)
endif

ifdef INCLUDED_COMPOSE_PROJECT_TARGETS
  $(error [ERROR] [Compose Go App Configuration] The Compose Project Targets must not be included before this file.)
endif


# --------------------------------
# Targets
# --------------------------------

up:: _deps-up


INCLUDED_COMPOSE_DEPS_UP := 1
