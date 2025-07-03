#!/usr/bin/env bash
#
# Simple script to find the first available TCP port starting from 5000.
# Usage:
#   ./find_free_port.sh
# Prints the port number to stdout and exits with 0.

set -euo pipefail

# Optionally allow overriding the starting port via env var or command line:
START_PORT="${1:-8080}"

PORT="$START_PORT"

while true; do
  # Check if we can open a TCP connection to localhost:$PORT using Bash's /dev/tcp feature
  if (echo >/dev/tcp/127.0.0.1/"${PORT}") &>/dev/null; then
    # If successful, port is in use -> increment and keep looking
    PORT=$((PORT + 1))
  else
    # Otherwise, it's free. Print it and exit.
    echo "$PORT"
    exit 0
  fi
done
