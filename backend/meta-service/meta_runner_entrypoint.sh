#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

: "${ENV:?ENV env var is required}"
: "${SERVICES:?SERVICES env var is required}"

echo "[INFO] Starting meta-service runner entrypoint..."

# Fetch shared LaunchDarkly key and Cloudflare secret
export BWS_PROJECT_NAME="shared-${ENV}"

LD_SDK_KEY_SHARED="$(./fetch_bws_secret.sh LD_SDK_KEY_SHARED | jq -r '.LD_SDK_KEY_SHARED // empty')"

if [[ -z "$LD_SDK_KEY_SHARED" || "$LD_SDK_KEY_SHARED" == "null" ]]; then
  echo "[ERROR] Could not retrieve 'LD_SDK_KEY_SHARED' from BWS." >&2
  exit 1
fi
export LD_SDK_KEY="$LD_SDK_KEY_SHARED"

REQUIRE_CF=false
FLAG_VALUE="$(./fetch_launchdarkly_flag.sh require_edge_auth | jq -r '.require_edge_auth' | tr '[:upper:]' '[:lower:]')"
if [[ "$FLAG_VALUE" == "true" ]]; then
  REQUIRE_CF=true
fi

if $REQUIRE_CF; then
  EDGE_AUTH_SECRET="$(./fetch_bws_secret.sh EDGE_AUTH_SECRET | jq -r '.EDGE_AUTH_SECRET // empty')"
  if [[ -z "$EDGE_AUTH_SECRET" || "$EDGE_AUTH_SECRET" == "null" ]]; then
    echo "[ERROR] LaunchDarkly requires Cloudflare but 'EDGE_AUTH_SECRET' not found in BWS." >&2
    exit 1
  fi
  export EDGE_AUTH_SECRET
  echo "[INFO] Cloudflare header enforcement enabled."
  envsubst < /etc/nginx/templates/cf-auth.conf.template > /etc/nginx/nginx.conf
else
  echo "[INFO] Cloudflare header enforcement disabled."
fi

ulimit -n 65535 || true
ulimit -u 65535 || true

IFS=' ' read -ra SERVICE_ARRAY <<< "$SERVICES"
for svc in "${SERVICE_ARRAY[@]}"; do
  (set -a && . /root/${svc}.env && exec /root/${svc}) &
done

/root/health_check &
exec nginx -g 'daemon off;'

