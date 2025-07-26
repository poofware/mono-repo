#!/usr/bin/env bash
#
# encryption.sh
#
# Provides two functions for encrypting/decrypting text using AES-256-CBC,
# salted + PBKDF2 (sha256, 10000 iterations), base64 output.
# Relies on $BWS_ACCESS_TOKEN being set in the environment.
#

set -euo pipefail

###############################################################################
# Function: encrypt_token
# Description: Encrypts the provided plaintext string and writes the
#              result (base64-encoded ciphertext) to stdout.
#
# Usage: encrypt_token "plaintext"
###############################################################################
encrypt_token() {
  if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
    echo "[ERROR] BWS_ACCESS_TOKEN must be set to encrypt the token." >&2
    return 1
  fi

  # Read plaintext argument
  local plaintext="$1"

  echo -n "${plaintext}" \
    | openssl enc -aes-256-cbc -salt -pbkdf2 -md sha256 -iter 10000 -base64 -A \
      -pass pass:"${BWS_ACCESS_TOKEN}"
  # Add a trailing newline so shell doesn't show a '%' after the file contents
  # Not strictly necessary, but a good practice
  echo
}

###############################################################################
# Function: decrypt_token
# Description: Decrypts the provided base64-encoded ciphertext string
#              and writes the plaintext to stdout.
#
# Usage: decrypt_token "ciphertext"
###############################################################################
decrypt_token() {
  if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
    echo "[ERROR] BWS_ACCESS_TOKEN must be set to decrypt the token." >&2
    return 1
  fi

  # Read ciphertext argument
  local ciphertext="$1"

  echo "${ciphertext}" \
    | openssl enc -d -aes-256-cbc -salt -pbkdf2 -md sha256 -iter 10000 -base64 -A \
      -pass pass:"${BWS_ACCESS_TOKEN}"
}

