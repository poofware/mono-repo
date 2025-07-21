#!/usr/bin/env bash
#
# stripe_listener_entrypoint.sh — LaunchDarkly–controlled Stripe CLI listener
#
# Behaviour:
#   • If LaunchDarkly flag `dynamic_stripe_webhook_endpoint` is **true**,
#     the listener is disabled and the script exits successfully with a warning.
#   • If the flag is **false**, the script:
#       1. Decrypts the BWS API token
#       2. Fetches `LD_SDK_KEY` (from BWS_PROJECT_NAME_FOR_ENABLE_LISTENER) and
#          evaluates the LaunchDarkly flag
#       3. Fetches `STRIPE_SECRET_KEY` (from BWS_PROJECT_NAME_FOR_STRIPE_SECRET)
#       4. Starts `stripe listen`, forwarding events to your app
#
# Required environment --------------------------------------------------------
#   APP_URL_FROM_COMPOSE_NETWORK
#   STRIPE_WEBHOOK_CONNECTED_EVENTS
#   STRIPE_WEBHOOK_PLATFORM_EVENTS
#   STRIPE_WEBHOOK_ROUTE
#   BWS_PROJECT_NAME_FOR_STRIPE_SECRET
#   BWS_PROJECT_NAME_FOR_ENABLE_LISTENER
# -----------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# 0. Required environment
###############################################################################
: "${APP_URL_FROM_COMPOSE_NETWORK:?APP_URL_FROM_COMPOSE_NETWORK env var is required}"
: "${STRIPE_WEBHOOK_ROUTE:?STRIPE_WEBHOOK_ROUTE env var is required}"
: "${BWS_PROJECT_NAME_FOR_STRIPE_SECRET:?BWS_PROJECT_NAME_FOR_STRIPE_SECRET env var is required}"
: "${BWS_PROJECT_NAME_FOR_ENABLE_LISTENER:?BWS_PROJECT_NAME_FOR_ENABLE_LISTENER env var is required}"

FORWARD_TO_URL="${APP_URL_FROM_COMPOSE_NETWORK}${STRIPE_WEBHOOK_ROUTE}"

###############################################################################
# 2. Fetch LD_SDK_KEY (for flag evaluation)
###############################################################################
export BWS_PROJECT_NAME="${BWS_PROJECT_NAME_FOR_ENABLE_LISTENER}"
echo "[INFO] Fetching 'LD_SDK_KEY' from BWS (app=${BWS_PROJECT_NAME})…"

LD_SDK_KEY="$(./fetch_bws_secret.sh LD_SDK_KEY | jq -r '.LD_SDK_KEY // empty')"

if [[ -z "${LD_SDK_KEY}" || "${LD_SDK_KEY}" == "null" ]]; then
  echo "[ERROR] Could not retrieve 'LD_SDK_KEY' from BWS." >&2
  exit 1
fi
export LD_SDK_KEY
echo "[INFO] Successfully fetched 'LD_SDK_KEY'."

###############################################################################
# 3. Evaluate LaunchDarkly flag
###############################################################################
echo "[INFO] Evaluating LaunchDarkly flag 'dynamic_stripe_webhook_endpoint'…"
STRIPE_FLAG="$(./fetch_launchdarkly_flag.sh dynamic_stripe_webhook_endpoint \
               | jq -r '.dynamic_stripe_webhook_endpoint' \
               | tr '[:upper:]' '[:lower:]')"

if [[ "${STRIPE_FLAG}" == "true" ]]; then
  echo "[WARN] LaunchDarkly flag 'dynamic_stripe_webhook_endpoint' is TRUE — Stripe listener is disabled. Exiting."
  exit 0
fi
echo "[INFO] Flag is FALSE — proceeding to start Stripe listener."

###############################################################################
# 4. Fetch STRIPE_SECRET_KEY (for Stripe CLI)
###############################################################################
export BWS_PROJECT_NAME="${BWS_PROJECT_NAME_FOR_STRIPE_SECRET}"
echo "[INFO] Fetching 'STRIPE_SECRET_KEY' from BWS (app=${BWS_PROJECT_NAME})…"

STRIPE_SECRET_KEY="$(./fetch_bws_secret.sh STRIPE_SECRET_KEY | jq -r '.STRIPE_SECRET_KEY // empty')"

if [[ -z "${STRIPE_SECRET_KEY}" || "${STRIPE_SECRET_KEY}" == "null" ]]; then
  echo "[ERROR] Could not retrieve 'STRIPE_SECRET_KEY' from BWS."
  exit 1
fi
echo "[INFO] Successfully fetched 'STRIPE_SECRET_KEY'."

###############################################################################
# 5. Validate events and launch Stripe CLI listener
###############################################################################
if [[ -z "${STRIPE_WEBHOOK_PLATFORM_EVENTS}" && -z "${STRIPE_WEBHOOK_CONNECTED_EVENTS}" ]]; then
  echo "[ERROR] No events specified in STRIPE_WEBHOOK_PLATFORM_EVENTS or STRIPE_WEBHOOK_CONNECTED_EVENTS."
  exit 1
fi

# Combine event lists (removes any accidental leading/trailing commas)
ALL_EVENTS="$(echo "${STRIPE_WEBHOOK_PLATFORM_EVENTS},${STRIPE_WEBHOOK_CONNECTED_EVENTS}" | sed 's/^,*//;s/,,*/,/;s/,*$//')"

echo "[INFO] Starting Stripe listener with forward-to: ${FORWARD_TO_URL}"
exec stripe listen \
     -e "${ALL_EVENTS}" \
     --forward-connect-to "${FORWARD_TO_URL}" \
     --forward-to "${FORWARD_TO_URL}" \
     --api-key "${STRIPE_SECRET_KEY}"

