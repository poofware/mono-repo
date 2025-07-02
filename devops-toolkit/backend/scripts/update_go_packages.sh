#!/usr/bin/env bash
#
# Usage:
#   ./update_go_packages.sh
#
# Before calling this script, ensure the environment variables are set:
#   PACKAGES="go-middleware go-utils go-repositories go-models"
#   BRANCH="develop"
#
# The script will fetch each configured Poof repository from GitHub
# at the specified branch/tag.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

if [ -z "$BRANCH" ] || [ -z "$PACKAGES" ]; then
  echo "[ERROR] [Update] BRANCH and PACKAGES environment variables must be set."
  echo "Example usage: BRANCH=develop PACKAGES=\"go-middleware go-utils go-repositories go-models\" ./update_go_packages.sh"
  exit 1
fi

echo "[INFO] [Update] Using branch: $BRANCH"
echo "[INFO] [Update] Using packages: $PACKAGES"

# 1) Export GOPRIVATE
echo "[INFO] [Update] Exporting GOPRIVATE=github.com/poofware/*"
export GOPRIVATE="github.com/poofware/*"

# 2) Set git config for github.com to use SSH instead of HTTPS (global)
if git config --global -l | grep -q 'url.git@github.com:.insteadof=https://github.com/'; then
  echo "[INFO] [Update] Git SSH config for github.com already set. Skipping."
else
  echo "[INFO] [Update] Config not found. Setting url.git@github.com:.insteadOf \"https://github.com/\""
  git config --global url."git@github.com:".insteadOf "https://github.com/"
fi

# 3) Fetch each package via go get
for PKG in $PACKAGES; do
  FULLNAME="github.com/poofware/$PKG"
  echo "[INFO] [Update] go get $FULLNAME@$BRANCH"
  if ! go get "$FULLNAME@$BRANCH"; then
    echo "[WARN] [Update] Failed to fetch $FULLNAME@$BRANCH. Continuing..."
  fi
done

# 4) Download all modules after updating references
echo "[INFO] [Update] Running go mod tidy to ensure all dependencies are pulled..."
go mod tidy

echo "[INFO] [Update] Successfully fetched all Poof go package repos at branch '$BRANCH'."
exit 0

