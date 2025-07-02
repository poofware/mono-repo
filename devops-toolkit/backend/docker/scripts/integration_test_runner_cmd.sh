#!/bin/bash
set -e

#!/bin/bash
set -e

: "${APP_URL_FROM_COMPOSE_NETWORK:?APP_URL_FROM_COMPOSE_NETWORK env var is required}"

# Health check loop: tries up to 10 times to confirm the service is up
n=10
while ! curl -sf "$APP_URL_FROM_COMPOSE_NETWORK/health" && [ $((n--)) -gt 0 ]; do
  echo "Waiting for service health from $APP_URL_FROM_COMPOSE_NETWORK..."
  sleep 2
done

if [ $n -le 0 ]; then
  echo "[ERROR] Failed to connect after 10 attempts." >&2
  exit 1
fi

echo "[INFO] Service is healthy!"

# Finally, run the integration tests
exec ./integration_test -test.v
