#!/bin/bash
set -e

: "${APP_URL_FROM_ANYWHERE:?APP_URL_FROM_ANYWHERE env var is required}"

# Health check loop: tries up to 10 times to confirm the service is up
n=10
while ! curl -sf "$APP_URL_FROM_ANYWHERE/health" >&2 && [ $((n--)) -gt 0 ]; do
  echo "Waiting for service health from $APP_URL_FROM_ANYWHERE..." >&2
  sleep 2
done

if [ $n -le 0 ]; then
  echo "[ERROR] Failed to connect after 10 attempts." >&2
  exit 1
fi

echo "[INFO] Service is healthy!" >&2
