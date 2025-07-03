# ------------------------------
# Compose App Targets
# ------------------------------

SHELL := /bin/bash

.PHONY: help

# Check that the current working directory is the root of a project by verifying that the root Makefile exists.
ifeq ($(wildcard Makefile),)
  $(error Error: Makefile not found. Please ensure you are in the root directory of your project.)
endif

ifndef INCLUDED_TOOLKIT_BOOTSTRAP
  $(error [toolkit] bootstrap.mk not included before $(lastword $(MAKEFILE_LIST)))
endif

ifndef INCLUDED_COMPOSE_APP_CONFIGURATION
  $(error [ERROR] [Compose App Configuration] The Compose App Configuration must be included before any Compose App Targets.)
endif

ifdef INCLUDED_COMPOSE_DEPS_TARGETS
  $(error [ERROR] [Compose App Configuration] The Compose Deps Targets must not be included before this file. \
	This file controls the inclusion of the deps targets strategically.)
endif

ifdef INCLUDED_COMPOSE_PROJECT_TARGETS
  $(error [ERROR] [Compose App Configuration] The Compose Project Targets must not be included before this file.)
endif


# --------------------------------
# Targets
# --------------------------------

ifeq ($(APP_IS_GATEWAY),1)
# If the app is a gateway to its dependencies, we need to passthrough some key network configurations to the deps targets.
# This ensures that the deps of the gateway app use the gateways addresses. This is important for obvious reasons.
DEPS_PASSTHROUGH_VARS += APP_URL_FROM_COMPOSE_NETWORK
DEPS_PASSTHROUGH_VARS += APP_URL_FROM_ANYWHERE
endif

ifneq (,$(filter $(ENV),$(DEV_TEST_ENV) $(DEV_ENV)))

  ifneq ($(APP_IS_GATEWAY),1)
    # If the app is not a gateway to its dependencies, we need to include the deps targets prior to the app targets.
    # This ensures that the app targets are run after the deps are built/up, ensuring no interference with the deps and vice versa.
    # Specifically, APP_HOST_PORT compute
    include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-targets/compose-deps-targets/compose_deps_targets.mk
  endif

  ifeq ($(ENABLE_NGROK_FOR_DEV),1)
    _export_ngrok_url_as_app_url:
    ifndef APP_URL_FROM_ANYWHERE
		@echo "[INFO] [Export Ngrok URL] Exporting ngrok URL as App Url From Anywhere..." >&2
		$(eval NGROK_HOST_PORT := $(shell $(COMPOSE_CMD) port ngrok $(NGROK_PORT) | cut -d ':' -f 2))
		$(eval export APP_URL_FROM_ANYWHERE := $(shell $(DEVOPS_TOOLKIT_PATH)/backend/scripts/get_ngrok_url.sh $(NGROK_HOST_PORT)))
		@echo "[INFO] [Export Ngrok URL] Done. App Url From Anywhere is set to: $(APP_URL_FROM_ANYWHERE)" >&2
    endif

    _up-ngrok: 
    # Only need to start ngrok once, but the target may be invoked multiple times.
    ifndef NGROK_UP
		$(eval export NGROK_UP := 1)
		@$(MAKE) _up-network --no-print-directory
		@echo "[INFO] [Up Ngrok] Starting 'ngrok' service..."
		@$(COMPOSE_CMD) up -d ngrok || exit 1
    endif

    ifeq ($(APP_IS_GATEWAY),1)
      DEPS_PASSTHROUGH_VARS += NGROK_UP
    endif

    build:: _up-ngrok _export_ngrok_url_as_app_url
    up:: _up-ngrok _export_ngrok_url_as_app_url
    print-public-app-domain:: _export_ngrok_url_as_app_url
  endif

  _export_app_host_port:
  ifndef APP_HOST_PORT
	  $(eval export APP_HOST_PORT := $(shell \
	    $(COMPOSE_CMD) port $(COMPOSE_PROFILE_APP_SERVICES) $(APP_PORT) 2>/dev/null \
	    | cut -d ':' -f2 | grep -E '^[0-9]+$$' || \
	    $(DEVOPS_TOOLKIT_PATH)/backend/scripts/find_available_port.sh 8080 \
	  ))
  endif

  build:: _export_app_host_port
  up:: _export_app_host_port

  ifneq ($(ENABLE_NGROK_FOR_DEV),1)
    _export_lan_url_as_app_url:
    ifndef APP_URL_FROM_ANYWHERE
		@echo "[INFO] [Export LAN URL] Exporting LAN URL as App Url From Anywhere..." >&2
		$(eval export APP_URL_FROM_ANYWHERE = http://$(shell $(DEVOPS_TOOLKIT_PATH)/backend/scripts/get_lan_ip.sh):$(APP_HOST_PORT))
		@echo "[INFO] [Export LAN URL] Done. App Url From Anywhere is set to: $(APP_URL_FROM_ANYWHERE)" >&2
    endif

    build:: _export_lan_url_as_app_url
    up:: _export_lan_url_as_app_url
    print-public-app-domain:: _export_app_host_port _export_lan_url_as_app_url
  endif

  # If the app is a gateway to apps that are in deps, we need to include the deps targets after the app targets.
  # This ensures that gateway app targets run first, causing the dependency apps to reuse the same exported network configurations.

else ifneq (,$(filter $(ENV),$(STAGING_ENV) $(STAGING_TEST_ENV)))
  
  _export_fly_api_token:
  ifndef FLY_API_TOKEN
	  $(eval export HCP_APP_NAME := shared-$(ENV))
	  $(eval export FLY_API_TOKEN := $(shell $(DEVOPS_TOOLKIT_PATH)/shared/scripts/fetch_hcp_secret_from_secrets_json.sh FLY_API_TOKEN))
	  $(if $(FLY_API_TOKEN),,$(error Failed to fetch HCP secret 'FLY_API_TOKEN'))
	  @echo "[INFO] [Export Fly Api Token] Fly API token set."
  endif

  DEPS_PASSTHROUGH_VARS += FLY_API_TOKEN

  _fly_wireguard_up:
  ifndef FLY_WIREGUARD_UP
	  $(eval export FLY_WIREGUARD_UP := 1)
	  @export LOG_LEVEL=; \
	  echo "[INFO] [Fly Wireguard Up] Calling Fly Wireguard Down target to ensure clean state..."; \
	  env -u MAKELEVEL $(MAKE) _fly_wireguard_down --no-print-directory; \
	  echo "[INFO] [Fly Wireguard Up] Creating WireGuard peer $(FLY_WIREGUARD_PEER_NAME) in region $(FLY_WIREGUARD_PEER_REGION) (with auto-retry)…"; \
	  set -e ; \
	  if fly wireguard create $(FLY_STAGING_ORG_NAME) \
	  	$(FLY_WIREGUARD_PEER_REGION) \
	  	$(FLY_WIREGUARD_PEER_NAME) \
	  	$(FLY_WIREGUARD_CONF_FILE); then \
	  	echo "[INFO] [Fly Wireguard Up] Peer created on first attempt." ; \
	  else \
		echo "[WARN] [Fly Wireguard Up] Peer creation failed – duplicate or peer-limit. Selecting a peer to delete…" ; \
		PEERS_JSON=$$(fly wireguard list $(FLY_STAGING_ORG_NAME) --json) ; \
		TARGET_PEER=$$(echo "$$PEERS_JSON" \
			| jq -r --arg name "$(FLY_WIREGUARD_PEER_NAME)" 'map(select(.Name==$$name))[0].Name // empty') ; \
		if [ -z "$$TARGET_PEER" ] ; then \
			TARGET_PEER=$$(echo "$$PEERS_JSON" | jq -r '.[-1].Name // empty') ; \
		fi ; \
		if [ -n "$$TARGET_PEER" ] ; then \
			echo "[INFO] [Fly Wireguard Up] Removing peer '$$TARGET_PEER'…"; \
			fly wireguard remove $(FLY_STAGING_ORG_NAME) $$TARGET_PEER || true ; \
		else \
			echo "[ERROR] [Fly Wireguard Up] No peers found to delete; aborting." ; \
			exit 1 ; \
		fi ; \
		fly wireguard create $(FLY_STAGING_ORG_NAME) \
			$(FLY_WIREGUARD_PEER_REGION) \
			$(FLY_WIREGUARD_PEER_NAME) \
			$(FLY_WIREGUARD_CONF_FILE) ; \
	  fi

	  @echo "[INFO] [Fly Wireguard Up] Starting WireGuard interface…"
	  @sudo wg-quick up $(FLY_WIREGUARD_CONF_FILE)
	  @echo "[INFO] [Fly Wireguard Up] Done – tunnel is live."
  endif

  DEPS_PASSTHROUGH_VARS += FLY_WIREGUARD_UP

  _fly_wireguard_down:
	  @if [ "$(MAKELEVEL)" -eq 0 ]; then \
		  export LOG_LEVEL=; \
		  echo "[INFO] [Fly Wireguard Down] Stopping wireguard connection to fly.io..."; \
		  sudo wg-quick down $(FLY_WIREGUARD_CONF_FILE) || echo "[WARN] [Fly Wireguard Down] Ignoring...no wireguard connection to fly.io found."; \
		  rm -f $(FLY_WIREGUARD_CONF_FILE); \
		  fly wireguard list $(FLY_STAGING_ORG_NAME) | grep -q "\b$(FLY_WIREGUARD_PEER_NAME)\b" && \
			  fly wireguard remove $(FLY_STAGING_ORG_NAME) $(FLY_WIREGUARD_PEER_NAME) || true; \
		  echo "[INFO] [Fly Wireguard Down] Done. Wireguard connection to fly.io is down."; \
	  fi

  integration-test:: _export_fly_api_token _fly_wireguard_up
  up:: _export_fly_api_token _fly_wireguard_up
  ci:: _export_fly_api_token _fly_wireguard_up
  clean:: _export_fly_api_token _fly_wireguard_up
  down:: _export_fly_api_token _fly_wireguard_up _up-network
	  @export LOG_LEVEL=; \
	  if [ "$(EXCLUDE_COMPOSE_PROFILE_APP)" -eq 1 ]; then \
		echo "[INFO] [Down] Skipping fly app destruction... EXCLUDE_COMPOSE_PROFILE_APP is set to 1"; \
	  else \
		echo "[INFO] [Down] Destroying app $(FLY_APP_NAME) on fly.io..."; \
		fly app destroy $(FLY_APP_NAME) --yes; \
		echo "[INFO] [Down] Done. App $(FLY_APP_NAME) destroyed."; \
	  fi; \
	  if [ -n "$(COMPOSE_PROFILE_MIGRATE_SERVICES)" ]; then \
		  echo "[INFO] [Down] Wiping the migrated isolated schema from the database..."; \
		  $(MAKE) migrate --no-print-directory MIGRATE_MODE=backward COMPOSE_PROFILE_MIGRATE_SERVICES="$(COMPOSE_PROFILE_MIGRATE_SERVICES)"; \
		  echo "[INFO] [Down] Done. Isolated schema wiped from the database."; \
	  fi
  migrate:: _export_fly_api_token _fly_wireguard_up

  ifndef INCLUDED_COMPOSE_PROJECT_TARGETS
    include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-targets/compose_project_targets.mk
  endif
  
  integration-test:: _fly_wireguard_down
  up:: _fly_wireguard_down
  ci:: _fly_wireguard_down
  clean:: _fly_wireguard_down
  down:: _fly_wireguard_down
  migrate:: _fly_wireguard_down

  # OVERRIDE default _up-app target to use fly.io instead of docker-compose
  _up-app:
	  @export LOG_LEVEL=; \
	  if fly app list -q | grep -q "\b$(FLY_APP_NAME)\b"; then \
		  echo "[INFO] [Up App] App $(FLY_APP_NAME) already exists. Skipping..."; \
	  else \
		  echo "[INFO] [Up App] Creating app $(FLY_APP_NAME) on fly.io..."; \
		  fly apps create $(FLY_APP_NAME) --org $(FLY_STAGING_ORG_NAME); \
		  echo "[INFO] [Up App] Done. App $(FLY_APP_NAME) created."; \
		  echo "[INFO] [Up App] Setting secrets for app $(FLY_APP_NAME)..."; \
		  fly secrets set HCP_TOKEN_ENC_KEY=$(HCP_TOKEN_ENC_KEY) --app $(FLY_APP_NAME); \
		  echo "[INFO] [Up App] Done. Secrets set for app $(FLY_APP_NAME)."; \
	  fi; \
	  echo "[INFO] [Up App] Starting app $(FLY_APP_NAME) on fly.io..."; \
	  fly deploy -a $(FLY_APP_NAME) -c $(STAGING_FLY_TOML_PATH) --image $(APP_NAME) --local-only --ha=false --yes; \
	  echo "[INFO] [Up App] Done. App $(FLY_APP_NAME) started."

else ifneq (,$(filter $(ENV),$(PROD_ENV)))
  # Prod not supported at this time.
endif

## Prints the domain that you can use to access the app from anywhere with https
print-public-app-domain::
	@$(DEVOPS_TOOLKIT_PATH)/backend/scripts/health_check.sh
	@echo $$APP_URL_FROM_ANYWHERE | sed -e 's~^https://~~'

ifndef INCLUDED_COMPOSE_PROJECT_TARGETS
  include $(DEVOPS_TOOLKIT_PATH)/backend/make/compose/compose-project-targets/compose_project_targets.mk
endif


INCLUDED_COMPOSE_APP_TARGETS := 1
