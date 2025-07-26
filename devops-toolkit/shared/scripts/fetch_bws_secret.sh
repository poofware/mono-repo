#!/usr/bin/env bash
#
# Usage:
#   ./fetch_bws_secret.sh [SECRET_NAME]
#
# Required environment variables
#   BWS_ACCESS_TOKEN   – machine‑account token used by the `bws` CLI :contentReference[oaicite:0]{index=0}
#   BWS_PROJECT_NAME   – exact name of the Bitwarden Secrets Manager project
#
# Optional overrides
#   BWS_PROJECT_ID     – set this to skip the name→ID lookup stage
#
# Dependencies: bash 4+, jq, the Bitwarden Secrets Manager CLI (`bws`)
#
set -euo pipefail

SECRET_NAME="${1:-}"

: "${BWS_ACCESS_TOKEN:?BWS_ACCESS_TOKEN env var is required}"
: "${BWS_PROJECT_NAME:?BWS_PROJECT_NAME env var is required}"

###############################################################################
# 1 ◆ Resolve project ID from name (unless BWS_PROJECT_ID is pre‑set)
###############################################################################
if [[ -n "${BWS_PROJECT_ID:-}" ]]; then
  PROJECT_ID="$BWS_PROJECT_ID"
else
  # Query projects visible to the access‑token and filter for an exact name match
  mapfile -t matches < <(
    bws project list --output json \
    | jq -r --arg n "$BWS_PROJECT_NAME" '.[] | select(.name == $n) | .id'
  )

  case "${#matches[@]}" in
    0)
      echo "[ERROR] No Bitwarden project named \"$BWS_PROJECT_NAME\" found." >&2
      exit 1
      ;;
    1)
      PROJECT_ID="${matches[0]}"
      ;;
    *)
      echo "[ERROR] Project name \"$BWS_PROJECT_NAME\" is ambiguous:" >&2
      printf '  • %s\n' "${matches[@]}" >&2
      echo "Specify BWS_PROJECT_ID to disambiguate." >&2
      exit 1
      ;;
  esac
fi

###############################################################################
# 2 ◆ Fetch secret(s) – retry once on failure
###############################################################################
for attempt in 1 2; do
  if [[ -n "$SECRET_NAME" ]]; then
    # Retrieve secrets for this project ID, then pick the desired key
    RESPONSE="$(bws secret list "$PROJECT_ID" --output json 2>/dev/null || true)"
    VALUE="$(echo "$RESPONSE" \
      | jq -r --arg k "$SECRET_NAME" 'map(select(.key == $k).value) | first // empty')"

    if [[ -n "$VALUE" ]]; then
      # Preserve native JSON if possible
      if echo "$VALUE" | jq -e . >/dev/null 2>&1; then
        printf '{"%s": %s}\n' "$SECRET_NAME" "$VALUE"
      else
        printf '{"%s": "%s"}\n' "$SECRET_NAME" "$VALUE"
      fi
      exit 0
    fi
    reason="secret not found"

  else
    RESPONSE="$(bws secret list "$PROJECT_ID" --output json 2>/dev/null || true)"
    if [[ -n "$RESPONSE" && "$RESPONSE" != "[]" ]]; then
      echo "$RESPONSE" | jq -r 'map({(.key): .value}) | add'
      exit 0
    fi
    reason="no secrets returned"
  fi

  # Simple two‑attempt retry
  if [[ $attempt -eq 1 ]]; then
    echo "[WARN] Attempt $attempt failed ($reason). Retrying in 5 s…" >&2
    sleep 5
  else
    echo "[ERROR] Failed after retry ($reason)." >&2
    exit 1
  fi
done

