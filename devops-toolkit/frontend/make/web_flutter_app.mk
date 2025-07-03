# --------------------------------
# Mobile Flutter App
# --------------------------------

SHELL := /bin/bash

.PHONY: run-web \
	build-web \
	e2e-test-web \
	integration-test-web \
	ci-web

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif


# --------------------------------
# Internal Variable Declaration
# --------------------------------

ifneq ($(origin FLUTTER_BASE_HREF), file)
  $(error FLUTTER_BASE_HREF is either not set or set as a runtime/ci environment variable, should be hardcoded in the root Makefile. \
	Example: FLUTTER_BASE_HREF="/pm/")
endif

ifndef INCLUDED_FLUTTER_APP_CONFIGURATION
  include $(DEVOPS_TOOLKIT_PATH)/frontend/make/utils/flutter_app_configuration.mk
endif

_DETECT_DRIVER = $(shell command -v chromedriver 2>/dev/null)
CHROMEDRIVER_BINARY = $(if $(_DETECT_DRIVER),$(_DETECT_DRIVER),\
  $(error [ERROR] chromedriver not found on PATH))

export CHROMEDRIVER_BINARY

# --------------------------------
# Targets
# --------------------------------

ifndef INCLUDED_FLUTTER_APP_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/frontend/make/utils/flutter_app_targets.mk
endif

integration-test-web: AUTO_LAUNCH_BACKEND ?= 1
integration-test-web: logs
	@case "$(ENV)" in \
	  $(DEV_TEST_ENV)|$(STAGING_TEST_ENV)) \
		$(call run_command_with_backend, \
		  echo "[INFO] [Integration Test] Running API tests on Web for ENV=$(ENV)..."; \
		  backend_export="$$( $(MAKE) _export_current_backend_domain --no-print-directory )"; \
		  rc=$$?; [ $$rc -eq 0 ] || exit $$rc; \
		  eval "$$backend_export"; \
		  set -eo pipefail; \
	      $(CHROMEDRIVER_BINARY) --port=4444 --verbose > logs/chromedriver_$(ENV).log 2>&1 & \
	      CD_PID=$$!; \
	      echo "[INFO] Chromedriver started => PID=$$CD_PID => port=4444"; \
		  trap 'echo "[CLEANUP] Killing Chromedriver $$CD_PID"; \
			kill -9 $$CD_PID 2>/dev/null || true' EXIT INT TERM; \
		  flutter drive \
			--driver=integration_test/driver.dart \
			--target=integration_test/api/api_test.dart \
			-d chrome \
			--browser-name=chrome \
			--driver-port=4444 \
			--keep-app-running \
			--dart-define=CURRENT_BACKEND_DOMAIN=$$CURRENT_BACKEND_DOMAIN \
			--dart-define=ENV=$(ENV) \
			--dart-define=LOG_LEVEL=$(LOG_LEVEL) \
			  $(VERBOSE_FLAG) 2>&1 \
			| tee logs/integration_test_web_$(ENV).log \
		); \
		;; \
	  *) \
		echo "Invalid ENV: $(ENV). Choose from [$(DEV_TEST_ENV)|$(STAGING_TEST_ENV)]."; exit 1;; \
	esac

# Run end-to-end (UI) tests for Web
e2e-test-web:
	@$(MAKE) _e2e-test --no-print-directory PLATFORM=web

## Run the app in a specific environment (ENV=dev|dev-test|staging|prod) for web
run-web:
	@$(MAKE) _run --no-print-directory PLATFORM=web

## Build command for Web (production, release mode)
build-web: logs
	@echo "[INFO] [Build Web] Building for ENV=$(ENV)..."
	@flutter build web --wasm --release --target lib/main/main_$(ENV).dart $(VERBOSE_FLAG) \
		--base-href $(FLUTTER_BASE_HREF) 2>&1 | tee logs/build_web.log
	@echo "[INFO] [Build Web] Build complete. Check logs/build_web.log for details."

## CI Web pipeline: Starts backend, runs both integration and e2e tests, and then shuts down backend
ci-web::
	@echo "[INFO] [CI] Starting pipeline..."
	@echo "[INFO] [CI] Calling 'down-backend' target to ensure clean state..."
	@$(MAKE) down-backend --no-print-directory
	@echo "[INFO] [CI] Calling 'integration-test-web' target..."
	@$(MAKE) integration-test-web --no-print-directory AUTO_LAUNCH_BACKEND=1
	@# $(MAKE) e2e-test-web --no-print-directory # TODO: implement e2e tests
	@echo "[INFO] [CI] Calling 'down-backend' target..."
	@$(MAKE) down-backend --no-print-directory
	@echo "[INFO] [CI] Pipeline complete."


INCLUDED_WEB_FLUTTER_APP := 1
