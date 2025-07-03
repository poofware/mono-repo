#!/usr/bin/env bash
#
# Usage:
#   ./fetch_hcp_secret.sh [SECRET_NAME]
#
# If SECRET_NAME is provided, fetch only that one secret.
# Otherwise, fetch all secrets for the specified app.
#
# Environment variables required:
#   HCP_API_TOKEN  - The API token to authenticate against HCP.
#   HCP_ORG_ID     - The HCP organization ID.
#   HCP_PROJECT_ID - The HCP project ID.
#   HCP_APP_NAME   - The HCP vault secrets app name (e.g., "auth-service-dev").

set -e

SECRET_NAME="$1"

# Basic checks for required environment variables
: "${HCP_API_TOKEN:?HCP_API_TOKEN env var is required}"
: "${HCP_ORG_ID:?HCP_ORG_ID env var is required}"
: "${HCP_PROJECT_ID:?HCP_PROJECT_ID env var is required}"
: "${HCP_APP_NAME:?HCP_APP_NAME env var is required}"

# Determine the URL for single secret vs all secrets
if [ -n "$SECRET_NAME" ]; then
  # Fetch one secret
  URL="https://api.cloud.hashicorp.com/secrets/2023-11-28/organizations/${HCP_ORG_ID}/projects/${HCP_PROJECT_ID}/apps/${HCP_APP_NAME}/secrets/${SECRET_NAME}:open"
else
  # Fetch all secrets
  URL="https://api.cloud.hashicorp.com/secrets/2023-11-28/organizations/${HCP_ORG_ID}/projects/${HCP_PROJECT_ID}/apps/${HCP_APP_NAME}/secrets:open"
fi

# ──────────────────────────────────────────────────────────
# Retry loop (max 2 attempts, 5-second delay)
# ──────────────────────────────────────────────────────────
for attempt in 1 2; do
  RESPONSE="$(curl --silent --show-error --location \
    "$URL" \
    --header "Authorization: Bearer ${HCP_API_TOKEN}")"
  curl_exit=$?

  reason="curl_error"
  success=false

  if [ "$curl_exit" -eq 0 ]; then
    # Curl succeeded; now verify the payload contains the secret(s)
    if [ -n "$SECRET_NAME" ]; then
      SECRET_VALUE="$(echo "$RESPONSE" | jq -r '.secret.static_version.value // empty')"
      if [ -n "$SECRET_VALUE" ]; then
        success=true
      else
        reason="secret value empty"
      fi
    else
      ALL_SECRETS="$(echo "$RESPONSE" | jq -r '
        if .secrets then
          .secrets | map({(.name): .static_version.value}) | add
        else
          null
        end
      ')"
      if [ -n "$ALL_SECRETS" ] && [ "$ALL_SECRETS" != "null" ]; then
        success=true
      else
        reason="no secrets returned"
      fi
    fi
  else
    reason="curl exit $curl_exit"
  fi

  $success && break

  if [ "$attempt" -eq 1 ]; then
    echo "[WARN] Attempt $attempt failed ($reason). Retrying in 5 s…" >&2
    sleep 5
  else
    echo "[ERROR] Failed after retry ($reason)." >&2
    if [ "$reason" = "secret value empty" ] && [ -n "$SECRET_NAME" ]; then
      echo "[ERROR] Could not retrieve the secret '$SECRET_NAME' for app '$HCP_APP_NAME'." >&2
      echo "[ERROR] Try the following:" >&2
      echo "[ERROR]     1. Check if the secret name is correct." >&2
      echo "[ERROR]     2. Check if the secret exists in the HCP app." >&2
      echo "[ERROR]     3. Check if the app name is correct." >&2
      echo "[ERROR]     4. Make sure the HCP API token is fresh and has proper permissions." >&2
    elif [ "$reason" = "no secrets returned" ] && [ -z "$SECRET_NAME" ]; then
      echo "[ERROR] No secrets found for app '$HCP_APP_NAME' or invalid response." >&2
    fi
    echo "Full response from HCP was:" >&2
    echo "$RESPONSE" >&2
    exit 1
  fi
done

# ──────────────────────────────────────────────────────────
# Successful path: output secrets (same style as original)
# ──────────────────────────────────────────────────────────
if [ -n "$SECRET_NAME" ]; then
  if echo "$SECRET_VALUE" | jq -e . >/dev/null 2>&1; then
    echo "{\"${SECRET_NAME}\": $SECRET_VALUE}"
  else
    echo "{\"${SECRET_NAME}\": \"${SECRET_VALUE}\"}"
  fi
else
  echo "$ALL_SECRETS"
fi

