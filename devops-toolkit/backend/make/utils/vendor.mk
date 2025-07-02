# --------------------------------
# Go Mod Vendor Target
# --------------------------------

SHELL := /bin/bash

INCLUDED_VENDOR := 1


ifndef INCLUDED_ENSURE_GO
  include $(DEVOPS_TOOLKIT)/backend/make/utils/ensure_go.mk
endif


## Updates vendor directory based on changes in go.mod or go.sum (disabled if vendor directory is empty, enable by running 'go mod vendor' once)
vendor.stamp: go.mod go.sum
	@if [ ! -d "vendor" ]; then \
		echo "[INFO] [Vendor] Initializing empty vendor directory..."; \
		mkdir -p vendor; \
	fi
	@if [ -z "$$(ls -A vendor)" ]; then \
		echo "[WARN] [Vendor] Vendoring is disabled due to an empty vendor directory. Enable by running 'go mod vendor' once."; \
	else \
		$(MAKE) --no-print-directory _ensure-go; \
		echo "[INFO] [Vendor] Vendoring is enabled due to the presence of a non-empty vendor directory."; \
		echo "[INFO] [Vendor] Updating vendor due to changes in go.mod or go.sum..."; \
		go mod vendor; \
		touch vendor.stamp; \
		echo "[INFO] [Vendor] Done. Vendor updated successfully."; \
	fi

vendor: vendor.stamp
