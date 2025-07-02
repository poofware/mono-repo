#!/usr/bin/env bash
#
# Usage:
#   ./fetch_hcp_secret_from_secrets_json.sh [SECRET_FIELD_NAME]
#
# If SECRET_FIELD_NAME is provided, fetch only that one field's value
# from the "SECRETS_JSON" secret. Otherwise, fetch the entire
# JSON from "SECRETS_JSON".
#
# Environment variables required:
#   HCP_API_TOKEN  - The API token to authenticate against HCP.
#   HCP_ORG_ID     - The HCP organization ID.
#   HCP_PROJECT_ID - The HCP project ID.
#   HCP_APP_NAME   - The application name (e.g., "auth-service").
#
# This script reuses the 'fetch_hcp_secret.sh' script in the same
# directory to retrieve the "SECRETS_JSON" secret and parse it.

set -e

# The field name within SECRETS_JSON we want to fetch.
# If empty, we'll return the entire SECRETS_JSON object.
SECRET_FIELD_NAME="$1"

# Basic checks for required environment variables
: "${HCP_API_TOKEN:?HCP_API_TOKEN env var is required}"
: "${HCP_ORG_ID:?HCP_ORG_ID env var is required}"
: "${HCP_PROJECT_ID:?HCP_PROJECT_ID env var is required}"
: "${HCP_APP_NAME:?HCP_APP_NAME env var is required}"

echo "[INFO] Fetching SECRETS_JSON from HCP app '$HCP_APP_NAME'..." >&2

RAW_RESPONSE="$("$(dirname "${BASH_SOURCE[0]}")/fetch_hcp_secret.sh" SECRETS_JSON)"

# 2. Extract the raw JSON string from the RAW_RESPONSE JSON.
SECRETS_JSON="$(echo "$RAW_RESPONSE" | jq -r '.SECRETS_JSON // empty')"

if [ -z "$SECRETS_JSON" ]; then
  echo "[ERROR] Could not retrieve the 'SECRETS_JSON' secret or it is empty." >&2
  echo "Full response was:" >&2
  echo "$RAW_RESPONSE" >&2
  exit 1
fi

# 3. If SECRET_FIELD_NAME is provided, parse just that field. Otherwise, print the whole JSON.
if [ -n "$SECRET_FIELD_NAME" ]; then
  echo "[INFO] Fetching secret field '$SECRET_FIELD_NAME' from SECRETS_JSON" >&2
  SECRET_FIELD_VALUE="$(echo "$SECRETS_JSON" | jq -r --arg field "$SECRET_FIELD_NAME" '.[$field] // empty')"
  if [ -z "$SECRET_FIELD_VALUE" ]; then
    echo "[ERROR] Could not find '$SECRET_FIELD_NAME' inside SECRETS_JSON." >&2
    exit 1
  fi

  echo "[INFO] Fetched secret '$SECRET_FIELD_NAME' successfully." >&2

  echo "$SECRET_FIELD_VALUE"
else
  
  echo "[INFO] Fetched SECRETS_JSON successfully." >&2

  # Print the entire JSON as-is
  echo "$SECRETS_JSON"
fi

