#!/usr/bin/env bash
set -euo pipefail        # make -e apply to every element of a pipeline

trap 'echo; echo "[INFO] Interrupted – exiting."; exit 130' INT  # honour Ctrl-C

NGROK_HOST_PORT=${1:-}
if [[ -z $NGROK_HOST_PORT ]]; then
  echo "[ERROR] ngrok host port is required." >&2
  echo "Usage: $0 <ngrok_host_port>" >&2
  exit 1
fi

echo "[INFO] Fetching ngrok tunnel URL..." >&2

while :; do
  # -s  silent, -f  fail with non-zero on HTTP error
  if NGROK_URL=$(curl -sf "http://localhost:${NGROK_HOST_PORT}/api/tunnels" \
                   | jq -r '.tunnels[0].public_url'); then
    if [[ -n $NGROK_URL && $NGROK_URL != null ]]; then
      echo "$NGROK_URL"
      exit 0
    fi
  fi

  echo "[INFO] Waiting for ngrok tunnel to be available…" >&2
  sleep 1        # SIGINT during this sleep now ends the script
done

