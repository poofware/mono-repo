#!/usr/bin/env bash
#
# fetch_hcp_api_token.sh
#
# A script to retrieve and output a HashiCorp Cloud Platform (HCP) access token
# using environment variables HCP_CLIENT_ID and HCP_CLIENT_SECRET.
# The token is *encrypted* at rest in a local cache file using $HCP_TOKEN_ENC_KEY.
# We reuse the token until it's close to expiration (3540 seconds).
#
# Usage:
#   ./fetch_hcp_api_token.sh [plain|encrypted]  (defaults to 'plain')
#     - plain: outputs the plaintext token
#     - encrypted: outputs the encrypted token
#
# Requirements:
#   - HCP_CLIENT_ID and HCP_CLIENT_SECRET (for fetching new token).
#   - HCP_TOKEN_ENC_KEY (passphrase for encrypting/decrypting the cached token).
#   - 'jq' installed, plus 'openssl' that supports -iter / -md sha256 / -pbkdf2.

set -euo pipefail

# -----------------------------------------------------------------------------
# Source the encryption library for encrypt_token / decrypt_token functions
# -----------------------------------------------------------------------------
source devops-toolkit/backend/scripts/encryption.sh

CACHE_FILE=".hcp_token_cache"
TOKEN_MAX_AGE=3540  # 59 minutes, to refresh a minute before actual 3600s expiry

# Determine output mode from optional first argument (defaults to 'plain')
OUTPUT_MODE="${1:-plain}"

###############################################################################
# Function: fetch_new_token
# Description: Fetches a new HCP token from HashiCorp's auth endpoint using
#              the required environment variables, then encrypts it to disk.
###############################################################################
fetch_new_token() {
  # Check that required environment variables are set
  if [[ -z "${HCP_CLIENT_ID:-}" || -z "${HCP_CLIENT_SECRET:-}" ]]; then
    echo "[ERROR] HCP_CLIENT_ID and HCP_CLIENT_SECRET environment variables must be set." >&2
    echo "[ERROR] Usage: HCP_CLIENT_ID=... HCP_CLIENT_SECRET=... ./fetch_hcp_api_token.sh" >&2
    exit 1
  fi
  if [[ -z "${HCP_TOKEN_ENC_KEY:-}" ]]; then
    echo "[ERROR] HCP_TOKEN_ENC_KEY environment variable must be set (ASCII passphrase)." >&2
    exit 1
  fi

  echo "[INFO] No valid cached HCP token (or it's expired). Fetching a new one..." >&2

  # Retrieve the token from HashiCorp's auth endpoint
  response="$(curl --silent --show-error --location "https://auth.idp.hashicorp.com/oauth2/token" \
    --header "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${HCP_CLIENT_ID}" \
    --data-urlencode "client_secret=${HCP_CLIENT_SECRET}" \
    --data-urlencode "grant_type=client_credentials" \
    --data-urlencode "audience=https://api.hashicorp.cloud")"

  if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to retrieve token (curl failed with non-zero exit code)." >&2
    echo "[ERROR] Full response from HCP was:" >&2
    echo "${response}" >&2
    exit 1
  fi

  # Extract the token using jq
  hcp_token="$(echo "${response}" | jq -r '.access_token')"

  # Verify we got a token
  if [[ -z "${hcp_token}" || "${hcp_token}" == "null" ]]; then
    echo "[ERROR] Failed to retrieve HCP access token." >&2
    echo "[ERROR] Response from server was: ${response}" >&2
    exit 1
  fi

  # Encrypt token -> cache file
  encrypt_token "${hcp_token}" > "${CACHE_FILE}"

  # Optionally secure the file (best effort)
  chmod 600 "${CACHE_FILE}" || true

  echo "[INFO] New HCP token fetched and cached (encrypted) successfully." >&2

  # Output either encrypted or plain token
  if [[ "${OUTPUT_MODE}" == "encrypted" ]]; then
    cat "${CACHE_FILE}"
  else
    echo "${hcp_token}"
  fi
}

###############################################################################
# Function: decrypt_cached_token
# Description: Decrypts the token from CACHE_FILE. If decryption fails, it
#              returns non-zero status to trigger re-fetch.
###############################################################################
decrypt_cached_token() {
  local ciphertext
  ciphertext="$(cat "${CACHE_FILE}")"
  if [[ -z "${HCP_TOKEN_ENC_KEY:-}" ]]; then
    echo "[ERROR] HCP_TOKEN_ENC_KEY must be set to decrypt the cache." >&2
    return 1
  fi

  # Decrypt from base64
  local plaintext
  set +e
  plaintext="$(decrypt_token "${ciphertext}" 2>/dev/null)"
  local exit_code=$?
  set -e

  if [[ $exit_code -ne 0 || -z "${plaintext}" ]]; then
    echo "[WARN] Failed to decrypt cached token. Possibly wrong passphrase or corrupted file." >&2
    return 1
  fi

  echo "${plaintext}"
}

###############################################################################
# Main script execution
###############################################################################

# If there's a cache file, check its modification time first
if [[ -f "${CACHE_FILE}" ]]; then
  # Cross-platform approach for file modification time
  last_modified=$(stat -c %Y "${CACHE_FILE}")

  current_time=$(date +%s)
  file_age=$(( current_time - last_modified ))

  if [[ "${file_age}" -lt "${TOKEN_MAX_AGE}" ]]; then
    # File is still "fresh" - try to decrypt it
    cached_token="$(decrypt_cached_token || true)"  # '|| true' so we don't exit on failure
    if [[ -n "${cached_token}" ]]; then
      # Successfully decrypted
      if [[ "${OUTPUT_MODE}" == "encrypted" ]]; then
        cat "${CACHE_FILE}"
      else
        echo "${cached_token}"
      fi
      exit 0
    else
      # Decryption failed - fetch a new token
      fetch_new_token
      exit 0
    fi
  else
    # File is older than TOKEN_MAX_AGE - fetch new token
    fetch_new_token
    exit 0
  fi
else
  # No file - fetch new token
  fetch_new_token
  exit 0
fi

