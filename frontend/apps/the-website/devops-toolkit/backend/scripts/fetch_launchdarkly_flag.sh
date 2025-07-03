#!/usr/bin/env bash
#
# Usage:
#   ./fetch_launchdarkly_flag.sh [FLAG_NAME]
#
# If FLAG_NAME is provided, fetch only that one LaunchDarkly flag’s default (fallthrough/off) value,
# using the nested `"key"` attribute from the flag definition as the JSON key.
# Otherwise, fetch all flags (as key:value pairs) for this environment.
#
# Environment variable required:
#   LD_SDK_KEY - The LaunchDarkly environment SDK key (secret).
#
# Examples:
#   export LD_SDK_KEY="sdk-1234567890abcdef"
#   ./fetch_launchdarkly_flag.sh          # Fetch all flags
#   ./fetch_launchdarkly_flag.sh app_url  # Fetch a single flag named "app_url"
#

set -e

FLAG_NAME="$1"

# Basic check for required environment variable
: "${LD_SDK_KEY:?LD_SDK_KEY env var is required}"

# Get the entire environment's flag configuration (not context-specific)
RESPONSE="$(curl --silent --show-error --location \
  --header "Authorization: ${LD_SDK_KEY}" \
  https://sdk.launchdarkly.com/sdk/latest-all)"

# If cURL fails at the network/connection level, we catch it here
if [ $? -ne 0 ]; then
  echo "[ERROR] Failed to reach LaunchDarkly or unexpected network error." >&2
  echo "Full response (if any) was:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

# Build a JSON object keyed by each flag’s nested "key" field.
# For the "effective" value of each flag:
#   - If "on" == true, use variations[ fallthrough.variation ]
#   - Otherwise, use variations[ offVariation ]
ALL_FLAGS="$(echo "$RESPONSE" | jq -r '
  .flags
  | to_entries
  | map(
      {
        # The output JSON key is taken from the nested `.value.key`.
        (.value.key): (
          if .value.on == true then
            .value.variations[ .value.fallthrough.variation ]
          else
            .value.variations[ .value.offVariation // 0]
          end
        )
      }
    )
  | add
')"

# Check if we got any valid flags back
if [ -z "$ALL_FLAGS" ] || [ "$ALL_FLAGS" = "null" ]; then
  echo "[ERROR] No flags found or invalid response from LaunchDarkly." >&2
  echo "Full JSON response was:" >&2
  echo "$RESPONSE" >&2
  exit 1
fi

if [ -n "$FLAG_NAME" ]; then
  # Extract the single requested flag’s value by nested key
  FLAG_VALUE="$(echo "$ALL_FLAGS" | jq -r --arg FLAG "$FLAG_NAME" '.[$FLAG]')"

  # If we got an empty result, that likely means the flag wasn’t found by its nested key
  if [ -z "$FLAG_VALUE" ] || [ "$FLAG_VALUE" = "null" ]; then
    echo "[ERROR] Could not retrieve the flag '$FLAG_NAME' by its nested \"key\" field." >&2
    echo "All available flags/values (by nested key) were:" >&2
    echo "$ALL_FLAGS" | jq >&2
    exit 1
  fi

  # Output the flag/value as a simple JSON object
  echo "{\"${FLAG_NAME}\": \"${FLAG_VALUE}\"}"
else
  # No single flag specified: output the entire JSON of flags keyed by nested .value.key
  echo "$ALL_FLAGS"
fi

