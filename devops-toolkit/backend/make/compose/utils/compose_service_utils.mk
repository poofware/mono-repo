# --------------------------------
# Docker Compose Service Utils
# --------------------------------

SHELL := /bin/bash

.PHONY: _check-failed-services _get_profile_services


# Function: get_profile_services
# Usage: $(call get_profile_services,<profile>)
get_profile_services = \
  $(strip $(if $(strip $(1)), \
    $(shell $(COMPOSE_CMD) --profile "$(1)" config --services | xargs), \
    $(error [ERROR] [Up] Please invoke 'get_profile_services' with PROFILE=<profile>.)))

_check-failed-services:
	@if [ -z "$(PROFILE_TO_CHECK)" ]; then \
	  echo "[ERROR] [Up] Please invoke '_check-failed-services' with PROFILE_TO_CHECK=<profile>."; \
	  exit 1; \
	fi
	@if [ -z "$(SERVICES_TO_CHECK)" ]; then \
	  echo "[ERROR] [Up] Please invoke '_check-failed-services' with SERVICES_TO_CHECK=<services>."; \
	  exit 1; \
	fi
	@echo "[INFO] [Up] Checking exit status of containers for '$(PROFILE_TO_CHECK)' services: $(SERVICES_TO_CHECK)"
	@FAILED_SERVICES=""; \
	for svc in $(SERVICES_TO_CHECK); do \
	  EXIT_CODE=$$( $(COMPOSE_CMD) ps --format json --filter status=exited $$svc | jq -r '.ExitCode' ); \
	  if [ "$$EXIT_CODE" != "0" ] && [ "$$EXIT_CODE" != "" ]; then \
	    FAILED_SERVICES="$$FAILED_SERVICES $$svc(exit:$$EXIT_CODE)"; \
	  fi; \
	done; \
	if [ -n "$$FAILED_SERVICES" ]; then \
	  echo "[ERROR] [Up] The following '$(PROFILE_TO_CHECK)' service(s) exited with a non-zero exit code: $$FAILED_SERVICES"; \
	  exit 1; \
	else \
	  echo "[INFO] [Up] All '$(PROFILE_TO_CHECK)' services appear healthy."; \
	fi


INCLUDED_COMPOSE_SERVICE_UTILS := 1
