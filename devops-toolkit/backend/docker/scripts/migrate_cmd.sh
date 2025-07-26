#!/usr/bin/env bash
#
# migrate_cmd.sh — LaunchDarkly–driven, isolated-schema capable
#                  now powered by **Tern** with flexible modes
#
# Flow:
#   0. Validate essential env vars
#   2. Fetch DB_URL and LD_SDK_KEY              (via BWS)
#   3. Ask LaunchDarkly for using_isolated_schema
#   4. Build / ensure isolated schema & schema-named role
#   5. Wait for DB readiness
#   6. Act according to MIGRATE_MODE & ENV
#   7. Run Tern migrations
#   8. Post-migration cleanup (if needed)
#
# Supported behaviour ---------------------------------------------------------
#   ENV=prod
#     - MIGRATE_MODE=forward|unset   : tern migrate --destination +1
#     - MIGRATE_MODE=backward        : tern migrate --destination -1
#
#   ENV≠prod
#     - MIGRATE_MODE=forward|unset   : tern migrate (to head)
#     - MIGRATE_MODE=backward        : tern migrate --destination 0
#                                       ⇢ if using an isolated schema:
#                                           • verify schema exists first
#                                           • drop it (and its role) afterwards
#
# Tern destination syntax reference: +N (forward N), -N (back N)
# ---------------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# 0. Required environment
###############################################################################
: "${ENV:?ENV env var is required (e.g. dev, staging, prod)}"
# MIGRATE_MODE is optional; defaults to "forward"
MIGRATE_MODE="$(echo "${MIGRATE_MODE:-forward}" | tr '[:upper:]' '[:lower:]')"

###############################################################################
# 2. Fetch DB_URL and LD_SDK_KEY secrets from BWS
###############################################################################
echo "[INFO] Fetching secrets from BWS…"

DB_URL="$(./fetch_bws_secret.sh DB_URL | jq -r '.DB_URL // empty')"
LD_SDK_KEY="$(./fetch_bws_secret.sh LD_SDK_KEY | jq -r '.LD_SDK_KEY // empty')"

if [[ -z "${DB_URL}"    || "${DB_URL}"    == "null" ]]; then
  echo "[ERROR] Could not retrieve 'DB_URL' from BWS." >&2
  exit 1
fi
if [[ -z "${LD_SDK_KEY}" || "${LD_SDK_KEY}" == "null" ]]; then
  echo "[ERROR] Could not retrieve 'LD_SDK_KEY' from BWS." >&2
  exit 1
fi
export LD_SDK_KEY
echo "[INFO] LD_SDK_KEY full length: ${LD_SDK_KEY}"
echo "[INFO] Secrets fetched."

###############################################################################
# Helper → extract password from postgres://user:pass@host/…
###############################################################################
db_password() {
  perl -pe 's#.*/[^:]+:([^@/]+)@.*#\1#'
}
DB_PASSWORD="$(printf '%s\n' "${DB_URL}" | db_password)"
MIGRATION_USER=""

###############################################################################
# 3. Evaluate LaunchDarkly flag
###############################################################################
echo "[INFO] Evaluating LaunchDarkly flag 'using_isolated_schema'…"
ISOLATED_FLAG="$(./fetch_launchdarkly_flag.sh using_isolated_schema \
                 | jq -r '.using_isolated_schema' | tr '[:upper:]' '[:lower:]')"


USE_ISOLATED_SCHEMA=false
[[ "${ISOLATED_FLAG}" == "true" ]] && USE_ISOLATED_SCHEMA=true

###############################################################################
# 4. Wait for database readiness
###############################################################################
echo "[INFO] Waiting for database readiness…"
attempts=10
while ! pg_isready -d "${DB_URL}" -t 1 >/dev/null 2>&1 && (( attempts-- > 0 )); do
  echo "  …still starting, ${attempts} tries left"
  sleep 1
done
if (( attempts < 0 )); then
  echo "[ERROR] Failed to connect to DB after 10 attempts." >&2
  exit 1
fi

###############################################################################
# 5. Build / ensure isolated schema & schema-named role
###############################################################################
EFFECTIVE_DB_URL="${DB_URL}"   # unchanged (no search_path or port tweaks)

if $USE_ISOLATED_SCHEMA; then
  echo "[INFO] Flag is TRUE – enabling isolated schema."

  : "${UNIQUE_RUNNER_ID:?UNIQUE_RUNNER_ID env var is required when isolation is enabled}"
  : "${UNIQUE_RUN_NUMBER:?UNIQUE_RUN_NUMBER env var is required when isolation is enabled}"

  ISOLATED_SCHEMA="$(echo "${UNIQUE_RUNNER_ID}-${UNIQUE_RUN_NUMBER}" \
                   | tr '[:upper:]' '[:lower:]')"
  MIGRATION_USER="${ISOLATED_SCHEMA}"

  if [[ "${MIGRATE_MODE}" != "backward" ]]; then
    echo "[INFO] Ensuring schema '${ISOLATED_SCHEMA}' exists…"
    psql "${DB_URL}" -v ON_ERROR_STOP=1 \
         -c "CREATE SCHEMA IF NOT EXISTS \"${ISOLATED_SCHEMA}\";" >/dev/null
  else
    if ! psql "${DB_URL}" -tAc \
          "SELECT 1 FROM pg_namespace WHERE nspname='${ISOLATED_SCHEMA}'" \
          | grep -q 1; then
      echo "[WARN] Isolated schema '${ISOLATED_SCHEMA}' does not exist — nothing to roll back."
      exit 0
    fi
    echo "[INFO] Skipping schema creation – running in backward mode."
  fi

  # -------------------------------------------------------------------------
  # Create or reuse a role whose *name == schema*
  # -------------------------------------------------------------------------
  echo "[INFO] Ensuring role '${MIGRATION_USER}' exists and can log in…"
  psql "${DB_URL}" -v ON_ERROR_STOP=1 <<SQL >/dev/null
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${MIGRATION_USER}') THEN
    CREATE ROLE "${MIGRATION_USER}" LOGIN PASSWORD '${DB_PASSWORD}';
  END IF;
END
\$\$;
GRANT USAGE, CREATE ON SCHEMA "${ISOLATED_SCHEMA}" TO "${MIGRATION_USER}";
ALTER ROLE "${MIGRATION_USER}" SET search_path = "${ISOLATED_SCHEMA}";
SQL

  # -------------------------------------------------------------------------
  # Rewrite connection string to use the isolated role instead of --user
  # -------------------------------------------------------------------------
  echo "[INFO] Rewriting connection string to use migration user '${MIGRATION_USER}'…"
  # Replace the user portion between 'postgres://' and the next ':' or '@'
  EFFECTIVE_DB_URL="$(echo "${DB_URL}" \
                       | sed -E "s#(postgres://)[^:/@]+#\1${MIGRATION_USER}#")"
else
  echo "[INFO] Flag is FALSE – running migrations against shared schema."
fi

###############################################################################
# 6. Act according to MIGRATE_MODE & ENV
###############################################################################
if [[ "${MIGRATE_MODE}" == "backward" && "${USE_ISOLATED_SCHEMA}" == true ]]; then
  if ! psql "${DB_URL}" -tAc \
        "SELECT 1 FROM pg_namespace WHERE nspname='${ISOLATED_SCHEMA}'" \
        | grep -q 1; then
    echo "[WARN] Isolated schema '${ISOLATED_SCHEMA}' does not exist — nothing to roll back."
    exit 0
  fi
fi

DESTINATION=""
DROP_ISOLATED_AFTER=false

case "${MIGRATE_MODE}" in
  forward|"")
    if [[ "${ENV}" == "prod" ]]; then
      echo "[INFO] (prod) Migrating forward one version…"
      DESTINATION="+1"
    else
      echo "[INFO] (non-prod) Migrating to latest version…"
      DESTINATION=""
    fi
    ;;
  backward)
    if [[ "${ENV}" == "prod" ]]; then
      echo "[INFO] (prod) Rolling back one version…"
      DESTINATION="-1"
    else
      echo "[INFO] (non-prod) Rolling back to version 0 (clean slate)…"
      DESTINATION="0"
      if $USE_ISOLATED_SCHEMA; then
        echo "[INFO] Will drop isolated schema and role after rollback."
        DROP_ISOLATED_AFTER=true
      fi
    fi
    ;;
  *)
    echo "[ERROR] Unknown MIGRATE_MODE '${MIGRATE_MODE}'. Allowed: forward, backward." >&2
    exit 1
    ;;
esac

###############################################################################
# Guaranteed isolated-schema teardown for non-prod backward migrations
###############################################################################
if [[ "${DROP_ISOLATED_AFTER}" == true ]]; then
  cleanup_isolated() {
    # Preserve tern’s exit status so CI can still fail on real errors
    exit_code=$?

    echo "[INFO] → Cleaning up isolated schema '${ISOLATED_SCHEMA}'"

    # 1. Shoot any connections that still hold locks
    psql "${DB_URL}" -v ON_ERROR_STOP=0 -q <<SQL || true
SELECT pg_terminate_backend(pid)
FROM   pg_stat_activity
WHERE ( usename = '${MIGRATION_USER}'
        OR query   ~* '\\y${ISOLATED_SCHEMA}\\y' )
  AND pid <> pg_backend_pid();
SQL

    # 2. Revoke & drop objects owned by the migration role (outside the schema)
    psql "${DB_URL}" -v ON_ERROR_STOP=0 -q \
         -c "DROP OWNED BY \"${MIGRATION_USER}\" CASCADE;" || true

    # 3. Drop schema and role with tight time-outs to avoid hanging
    PGOPTIONS='-c lock_timeout=5s -c statement_timeout=30s' \
      psql "${DB_URL}" -v ON_ERROR_STOP=0 -q \
           -c "DROP SCHEMA IF EXISTS \"${ISOLATED_SCHEMA}\" CASCADE;" || true

    PGOPTIONS='-c lock_timeout=5s -c statement_timeout=30s' \
      psql "${DB_URL}" -v ON_ERROR_STOP=0 -q \
           -c "DROP ROLE IF EXISTS \"${MIGRATION_USER}\";" || true

    echo "[INFO] ✓ Isolated schema and role dropped."

    exit "${exit_code}"
  }

  # Invoke cleanup on *any* exit path (success, error, or interrupt)
  trap cleanup_isolated EXIT
fi

###############################################################################
# 6½. Skip the +1 if we're already at head (keeps 1‑step‑forward policy)
###############################################################################
if [[ "${ENV}" == "prod" && "${DESTINATION}" == "+1" ]]; then
  vt="schema_version"
  [[ -n "${ISOLATED_SCHEMA:-}" ]] && vt="\"${ISOLATED_SCHEMA}\".schema_version"

  current=$(psql "${EFFECTIVE_DB_URL}" -Atq -c "select version from ${vt} limit 1")
  latest=$(ls migrations | grep -E '^[0-9]+' | cut -d_ -f1 | sort -n | tail -1)

  if [[ -z "${current}" ]]; then current=0; fi

  if (( current >= latest )); then
    echo "[INFO] Database is already at latest version (${latest}); skipping."
    exit 0
  fi
fi

###############################################################################
# 7. Run Tern migrations
###############################################################################
echo "[INFO] Running migrations with Tern…"

EXTRA_TERN_ARGS=()
if $USE_ISOLATED_SCHEMA; then
  EXTRA_TERN_ARGS+=(--version-table "\"${ISOLATED_SCHEMA}\".schema_version")
fi

if [[ -n "${DESTINATION:-}" ]]; then
  time tern migrate \
       --migrations migrations \
       --conn-string "${EFFECTIVE_DB_URL}" \
       --destination "${DESTINATION}" \
       "${EXTRA_TERN_ARGS[@]}"
else
  time tern migrate \
       --migrations migrations \
       --conn-string "${EFFECTIVE_DB_URL}" \
       "${EXTRA_TERN_ARGS[@]}"
fi
