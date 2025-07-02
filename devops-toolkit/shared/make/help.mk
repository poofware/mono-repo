# ----------------------
# Help Target
# ----------------------

SHELL := /bin/bash

.PHONY: help

INCLUDED_HELP := 1


## Lists all available targets and any additional information about the project
help::
	@echo "----------------------------------------"
	@echo "[INFO] Available targets:"; \
	echo "----------------------------------------"; \
	awk 'BEGIN { FS=":.*" } \
	     /^##/ { desc = substr($$0, 4); next } \
	     /^[^_][a-zA-Z0-9_-]*:/ { \
	       if (desc != "") { \
	         tmp = desc; gsub(/[# ]/, "", tmp); \
	         if (length(tmp) > 0) { printf "\033[36m%-20s\033[0m %s\n", $$1, desc } \
	       } \
	       desc = "" \
	     }' $(MAKEFILE_LIST) | sort
	@echo "----------------------------------------"
	@echo
