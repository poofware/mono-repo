#!/bin/bash
###############################################################################
# ssh-docker-build.sh
#
# Build all or one docker image, passing the SSH key automatically
# Some host systems don't have a default SSH_AUTH_SOCK or
# the default agent is not configured with keys (macOS).
#
# Usage:
#   ./ssh-docker-build.sh compose [ARGS...]
#     -> runs "docker compose [ARGS...] --ssh default=$SSH_AUTH_SOCK ..."
#
#   ./ssh-docker-build.sh docker [ARGS...]
#     -> runs "docker build [ARGS...] --ssh default=$SSH_AUTH_SOCK ..."
#
# Also respects VERBOSE=1 to set --progress=plain vs. auto.
###############################################################################

set -euo pipefail

echo "[INFO] [Build] Starting dedicated SSH Agent..."
eval "$(ssh-agent -s)" >/dev/null 2>&1

echo "[INFO] [Build] Adding all private keys from ~/.ssh (non-.pub)"
for key in $(ls ~/.ssh/id_* 2>/dev/null || true); do
  if [[ -f "$key" && ! "$key" =~ \.pub$ ]]; then
    echo "   -> Adding key: $key"
    ssh-add "$key" >/dev/null 2>&1 || true
  fi
done

# Enable Docker BuildKit
export DOCKER_BUILDKIT=1
export COMPOSE_DOCKER_CLI_BUILD=1
export COMPOSE_BAKE=false

progress=${VERBOSE:+plain}; progress=${progress:-auto}
echo "[INFO] [Build] SSH_AUTH_SOCK=$SSH_AUTH_SOCK"
echo "[INFO] [Build] progress=$progress"

docker "$@" \
  --ssh "default=$SSH_AUTH_SOCK" \
  --progress="$progress"

echo "[INFO] [Build] Killing ssh-agent..."
ssh-agent -k >/dev/null 2>&1
echo "[INFO] [Build] Docker images built successfully."
