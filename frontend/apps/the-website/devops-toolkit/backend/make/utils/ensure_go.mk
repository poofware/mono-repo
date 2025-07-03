# --------------------------------
# Ensure Go
# --------------------------------

SHELL := /bin/bash

.PHONY: _ensure-go

INCLUDED_ENSURE_GO := 1


## Ensures Go is installed and the correct version is available in your PATH
_ensure-go:
	@if [ -z "$(GO_VERSION)" ]; then \
		echo "[ERROR] [Ensure Go] GO_VERSION is not set. Please define it in your local Makefile or environment. Example: GO_VERSION=1.16"; \
		exit 1; \
	fi
	@command -v go >/dev/null 2>&1 || { \
		echo "[ERROR] [Ensure Go] Go is not installed or not in your PATH."; \
		echo "[ERROR] [Ensure Go] Please install Go from https://golang.org/dl/ and ensure it's available in your PATH."; \
		exit 1; \
	}
	@CURRENT_GO_VERSION=$$(go version | grep -Eo '[0-9]+\.[0-9]+'); \
	if [ "$$(printf '%s\n%s' "$(GO_VERSION)" "$$CURRENT_GO_VERSION" | sort -V | head -n1)" != "$(GO_VERSION)" ]; then \
		echo "[ERROR] [Ensure Go] Go version $$CURRENT_GO_VERSION detected. Version $(GO_VERSION) or higher is required."; \
		exit 1; \
	fi

