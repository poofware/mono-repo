#!/bin/bash
set -e

echo "[INFO] Starting stripe-webhook-check-entrypoint..."

: "${HCP_ENCRYPTED_API_TOKEN:?HCP_ENCRYPTED_API_TOKEN env var is required}"
: "${APP_URL_FROM_ANYWHERE:?APP_URL_FROM_ANYWHERE env var is required}"
: "${STRIPE_WEBHOOK_CHECK_ROUTE:?STRIPE_WEBHOOK_CHECK_ROUTE env var is required}"
: "${APP_NAME:?APP_NAME env var is required}"
: "${UNIQUE_RUN_NUMBER:?UNIQUE_RUN_NUMBER env var is required}"
: "${UNIQUE_RUNNER_ID:?UNIQUE_RUNNER_ID env var is required}"

# 1) Wait for the service to be healthy
source ./health_check.sh

# 2) Decrypt the HCP token if needed
source ./encryption.sh
export HCP_API_TOKEN="$(decrypt_token "${HCP_ENCRYPTED_API_TOKEN}")"
echo "[INFO] Decrypted HCP_API_TOKEN successfully."

# 3) Fetch Stripe secret from HCP for CLI usage
STRIPE_SECRET_KEY="$(./fetch_hcp_secret_from_secrets_json.sh STRIPE_SECRET_KEY)"

if [ -z "$STRIPE_SECRET_KEY" ] || [ "$STRIPE_SECRET_KEY" = "null" ]; then
  echo "[ERROR] Could not retrieve 'STRIPE_SECRET_KEY' from HCP."
  exit 1
fi
echo "[INFO] 'STRIPE_SECRET_KEY' fetched from HCP."

# 4) Set up a trap to ensure the connected account is always deleted
ACCOUNT_ID=""
cleanup() {
  if [ -n "$ACCOUNT_ID" ]; then
    echo "[INFO] Deleting connected account ID: $ACCOUNT_ID"
    stripe accounts delete "$ACCOUNT_ID" \
      --api-key "$STRIPE_SECRET_KEY" -c || true
  fi
}
trap cleanup EXIT

# 5) Create a connected account
echo "[INFO] Creating an Express connected account..."
ACCOUNT_CREATE_OUTPUT="$(stripe accounts create --type=express --api-key "$STRIPE_SECRET_KEY")"
if [ -z "$ACCOUNT_CREATE_OUTPUT" ]; then
  echo "[ERROR] Failed to create a connected account."
  exit 1
fi

ACCOUNT_ID="$(echo "$ACCOUNT_CREATE_OUTPUT" | jq -r '.id // empty')"
if [ -z "$ACCOUNT_ID" ]; then
  echo "[ERROR] Could not parse 'id' from connected account creation response."
  echo "==== RAW CREATE OUTPUT ===="
  echo "$ACCOUNT_CREATE_OUTPUT"
  exit 1
fi
echo "[INFO] Created connected account: $ACCOUNT_ID"

# 6) Trigger a 'payment_intent.created' event with metadata
METADATA_VALUE="webhook_check-${APP_NAME}-${UNIQUE_RUNNER_ID}-${UNIQUE_RUN_NUMBER}"
echo "[INFO] Triggering Stripe event: payment_intent.created (connected account: $ACCOUNT_ID)"
echo "[INFO] Using metadata 'generated_by=${METADATA_VALUE}'"

set +e
TRIGGER_OUTPUT=$(timeout 15s stripe trigger payment_intent.created \
  --stripe-account "$ACCOUNT_ID" \
  --add "payment_intent:metadata.generated_by=${METADATA_VALUE}" \
  --api-key "$STRIPE_SECRET_KEY" 2>&1)
TRIGGER_EXIT=$?
set -e

if [ $TRIGGER_EXIT -ne 0 ]; then
  echo "[ERROR] 'stripe trigger payment_intent.created' command failed or timed out (exit code: $TRIGGER_EXIT)."
  echo "==== FULL TRIGGER OUTPUT ===="
  echo "$TRIGGER_OUTPUT"
  echo "==== END TRIGGER OUTPUT ===="
  exit 1
fi

if [ -z "$TRIGGER_OUTPUT" ]; then
  echo "[WARN] 'stripe trigger' returned empty output for payment_intent.created."
fi

# Allow a brief pause so Stripe can register the event
sleep 2

# 7) Get the single most recent event for this connected account
echo "[INFO] Fetching the last event from Stripe (connected account: $ACCOUNT_ID)..."
set +e
EVENTS_JSON=$(stripe events list \
  --limit 3 \
  --stripe-account "$ACCOUNT_ID" \
  --api-key "$STRIPE_SECRET_KEY" 2>&1)
EVENTS_EXIT=$?
set -e

if [ $EVENTS_EXIT -ne 0 ]; then
  echo "[ERROR] 'stripe events list' command failed (exit code: $EVENTS_EXIT)."
  echo "==== FULL EVENTS OUTPUT ===="
  echo "$EVENTS_JSON"
  echo "==== END EVENTS OUTPUT ===="
  exit 1
fi

if [ -z "$EVENTS_JSON" ]; then
  echo "[ERROR] 'stripe events list' returned no data."
  exit 1
fi

# 8) Parse the event ID
EVENT_ID=$(echo "$EVENTS_JSON" | jq -r '.data[] | select(.type == "payment_intent.created") | .id // empty')
if [ -z "$EVENT_ID" ]; then
  echo "[ERROR] Could not parse an event id from the last event."
  echo "==== RAW EVENTS JSON ===="
  echo "$EVENTS_JSON"
  exit 1
fi
echo "[INFO] Found triggered event ID: $EVENT_ID"

# 9) Poll the check endpoint to ensure the event was received by your app
CHECK_URL="${APP_URL_FROM_ANYWHERE}${STRIPE_WEBHOOK_CHECK_ROUTE}"
CHECK_URL_WITH_ARG="${CHECK_URL}?id=${EVENT_ID}"
echo "[INFO] Checking event at: $CHECK_URL_WITH_ARG"

attempts=10
while [ $attempts -gt 0 ]; do
  STATUS=$(curl -s -o /dev/null -w '%{http_code}' "$CHECK_URL_WITH_ARG" || true)
  if [ "$STATUS" = "200" ]; then
    echo "[INFO] Webhook event $EVENT_ID was received successfully!"
    echo "[INFO] Webhook check completed successfully."
    exit 0
  fi

  echo "[INFO] Webhook event $EVENT_ID not found yet (HTTP $STATUS). Retrying..."
  attempts=$((attempts - 1))
  sleep 2
done

echo "[ERROR] Timed out waiting for webhook event $EVENT_ID to be recognized by the service."
exit 1

