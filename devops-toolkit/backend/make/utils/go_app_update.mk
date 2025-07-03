# -----------------------
# Go App Update Target
# -----------------------

SHELL := /bin/bash

.PHONY: update

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

# Check that the current working directory is the root of a Go app by verifying that go.mod exists.
ifeq ($(wildcard go.mod),)
  $(error Error: go.mod not found. Please ensure you are in the root directory of your Go app.)
endif

INCLUDED_GO_APP_UPDATE := 1


ifndef INCLUDED_ENSURE_GO
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/utils/ensure_go.mk
endif


## Updates Go packages versions for this project to their latest on specified branch (requires BRANCH to be set, e.g. BRANCH=main, applies to all packages)
update: _ensure-go
	@echo "[INFO] [Update] Updating Go packages..."
	@if [ -z "$(BRANCH)" ]; then \
		echo "[ERROR] [Update] BRANCH is not set. Please pass it as an argument to the make command. Example: BRANCH=main make update"; \
		exit 1; \
	fi
	@if [ -z "$(PACKAGES)" ]; then \
		echo "[ERROR] [Update] PACKAGES is empty. No packages to update."; \
		exit 1; \
	fi

	@$(DEVOPS_TOOLKIT_PATH)/backend/scripts/update_go_packages.sh

	@echo "[INFO] [Update] Done."

