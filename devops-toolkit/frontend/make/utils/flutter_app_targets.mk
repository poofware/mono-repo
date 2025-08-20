# --------------------------------
# Flutter App Configuration
# --------------------------------

SHELL := /bin/bash

.PHONY: help check up-backend down-backend clean-backend logs \
	_run-env _run _integration-test _e2e-test clean \
	_export_current_backend_domain

# Check that the current working directory is the root of a Flutter app by verifying that pubspec.yaml exists.
ifeq ($(wildcard pubspec.yaml),)
  $(error Error: pubspec.yaml not found. Please ensure you are in the root directory of your Flutter app.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

ifndef INCLUDED_FLUTTER_APP_CONFIGURATION
  $(error [ERROR] [Flutter App Targets] The Flutter App Configuration must be included before any Flutter App Targets. \
	Include $$(DEVOPS_TOOLKIT_PATH)/frontend/make/utils/flutter_app_configuration.mk in your root Makefile.)
endif


# --------------------------------
# Targets
# --------------------------------

ifndef INCLUDED_HELP
  include $(DEVOPS_TOOLKIT_PATH)/shared/make/help.mk
endif

logs:
	@mkdir -p logs

## Run flutter doctor
check:
	@flutter doctor

## Up the backend
up-backend:
	@echo "[INFO] [Up Backend] Starting backend for ENV=$(ENV)..."
	@$(MAKE) -C $(BACKEND_GATEWAY_PATH) up PRINT_INFO=0

## Down the backend
down-backend:
	@echo "[INFO] [Down Backend] Stopping backend for ENV=$(ENV)..."
	@$(MAKE) -C $(BACKEND_GATEWAY_PATH) down PRINT_INFO=0

## Clean the backend
clean-backend:
	@echo "[INFO] [Clean Backend] Cleaning backend for ENV=$(ENV)..."
	@$(MAKE) -C $(BACKEND_GATEWAY_PATH) clean PRINT_INFO=0

# --------------------------------
# Export the current backend domain based on the environment
# --------------------------------
_backend_domain_cmd = $(MAKE) -C $(BACKEND_GATEWAY_PATH) \
                      --no-print-directory PRINT_INFO=0 print-public-app-domain

_export_current_backend_domain:
	@echo "[INFO] [Export Backend Domain] Exporting backend domain for ENV=$(ENV)..." >&2
ifneq (,$(filter $(ENV),$(DEV_TEST_ENV)))
	@if [ -z "$$CURRENT_BACKEND_DOMAIN" ]; then \
		domain="$$( $(_backend_domain_cmd) )"; rc=$$?; \
		[ $$rc -eq 0 ] || exit $$rc; \
		echo "export CURRENT_BACKEND_DOMAIN=\"$$domain\""; \
	fi
else
	@domain="$$( $(_backend_domain_cmd) )"; rc=$$?; \
	[ $$rc -eq 0 ] || exit $$rc; \
	echo "export CURRENT_BACKEND_DOMAIN=\"$$domain\""
endif

# Run API integration tests (non-UI logic tests)
_integration-test: AUTO_LAUNCH_BACKEND ?= 1
_integration-test: logs
	@case "$(ENV)" in \
	  $(DEV_TEST_ENV)|$(STAGING_TEST_ENV)) \
	    $(call run_command_with_backend, \
	      echo "[INFO] [Integration Test] Running API tests for ENV=$(ENV)..."; \
		  backend_export="$$( $(MAKE) _export_current_backend_domain --no-print-directory )"; \
		  rc=$$?; [ $$rc -eq 0 ] || exit $$rc; \
		  eval "$$backend_export"; \
		  set -eo pipefail; \
	      flutter test integration_test/api --dart-define=CURRENT_BACKEND_DOMAIN=$$CURRENT_BACKEND_DOMAIN \
		  --dart-define=GCP_SDK_KEY=$(GCP_SDK_KEY) \
		  --dart-define=ENV=$(ENV) --dart-define=LOG_LEVEL=$(LOG_LEVEL) $(VERBOSE_FLAG) 2>&1 | tee logs/integration_test_$(PLATFORM)_$(ENV).log \
	    ); \
	    ;; \
	  *) \
	    echo "Invalid ENV: $(ENV). Choose from [$(DEV_TEST_ENV)|$(STAGING_TEST_ENV)]."; exit 1;; \
	esac

# Run end-to-end (UI) tests
_e2e-test: AUTO_LAUNCH_BACKEND ?= 1
_e2e-test: logs
	@case "$(ENV)" in \
	  $(DEV_TEST_ENV)|$(STAGING_TEST_ENV)) \
	    $(call run_command_with_backend, \
	      echo "[INFO] [E2E Test] Running UI tests for ENV=$(ENV)..."; \
		  backend_export="$$( $(MAKE) _export_current_backend_domain --no-print-directory )"; \
		  rc=$$?; [ $$rc -eq 0 ] || exit $$rc; \
		  eval "$$backend_export"; \
		  set -eo pipefail; \
	      flutter test integration_test/e2e --dart-define=CURRENT_BACKEND_DOMAIN=$$CURRENT_BACKEND_DOMAIN \
		  --define=GCP_SDK_KEY=$(GCP_SDK_KEY) \
		  --dart-define=ENV=$(ENV) --dart-define=LOG_LEVEL=$(LOG_LEVEL) $(VERBOSE_FLAG) 2>&1 | tee logs/e2e_test_$(PLATFORM)_$(ENV).log \
	    ); \
	    ;; \
	  *) \
	    echo "Invalid ENV: $(ENV). Choose from [$(DEV_TEST_ENV)|$(STAGING_TEST_ENV)]."; exit 1;; \
	esac

# Run the app in a specific environment (ENV=dev|dev-test|staging|prod)
# Run the app in a specific environment (ENV=dev|dev-test|staging|prod)
_run-env: logs
	@echo "[INFO] Running Flutter app for ENV=$(ENV) on PLATFORM=$(PLATFORM)"
	@$(call run_command_with_backend, \
		backend_export="$$( $(MAKE) _export_current_backend_domain --no-print-directory )"; \
		rc=$$?; [ $$rc -eq 0 ] || exit $$rc; \
		eval "$$backend_export"; \
		set -eo pipefail; \
		web_flags=""; \
		if [ "$(PLATFORM)" = "web" ]; then \
			web_flags="-d chrome"; \
		fi; \
		flutter run $$web_flags --target lib/main/main_$(ENV).dart --dart-define=CURRENT_BACKEND_DOMAIN=$$CURRENT_BACKEND_DOMAIN \
		--dart-define=GCP_SDK_KEY=$(GCP_SDK_KEY) \
		--dart-define=LOG_LEVEL=$(LOG_LEVEL) $(VERBOSE_FLAG) 2>&1 | tee logs/run_$(PLATFORM)_$(ENV).log);

# Run the app in a specific environment (ENV=dev|dev-test|staging|prod) with respective auto backend behavior
_run: AUTO_LAUNCH_BACKEND ?= 1
_run:
	@case "$(ENV)" in \
	  $(DEV_ENV)|$(STAGING_ENV)) \
	    $(MAKE) _run-env --no-print-directory AUTO_LAUNCH_BACKEND=$(AUTO_LAUNCH_BACKEND) ENV=$(ENV); \
	    ;; \
	  $(DEV_TEST_ENV)) \
	  	echo "[WARN] [Run] Running ENV=dev-test, backend is not required, setting the domain to 'example.com'."; \
	  	export CURRENT_BACKEND_DOMAIN="example.com"; \
	    $(MAKE) _run-env --no-print-directory AUTO_LAUNCH_BACKEND=0 ENV=$(ENV); \
	    ;; \
	  $(PROD_ENV)) \
	    $(MAKE) _run-env --no-print-directory AUTO_LAUNCH_BACKEND=0 ENV=$(ENV); \
	    ;; \
	  *) \
	    echo "[ERROR] [Run] Invalid ENV: $(ENV). Choose from [$(DEV_ENV)|$(DEV_TEST_ENV)|$(STAGING_ENV)|$(PROD_ENV)]."; exit 1;; \
	esac

help::
	@echo "--------------------------------------------------"
	@echo "[INFO] Flutter App Configuration:"
	@echo "--------------------------------------------------"
	@echo "ENV: $(ENV)"
	@echo "VERBOSE: $(VERBOSE)"
	@echo "BACKEND_GATEWAY_PATH: $(BACKEND_GATEWAY_PATH)"
	@echo


INCLUDED_FLUTTER_APP_TARGETS := 1
