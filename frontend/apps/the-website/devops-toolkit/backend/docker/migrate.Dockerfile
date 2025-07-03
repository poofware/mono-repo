# ----------------------------------------------------------------------
#  Stage 1 – build the Tern CLI at the exact version we want
# ----------------------------------------------------------------------
FROM golang:1.22-alpine AS tern-build

# Pin to the newest tagged release so every build is repeatable
# (see https://github.com/jackc/tern/releases)
ARG TERN_VERSION=v2.3.2

ENV CGO_ENABLED=0
RUN apk add --no-cache git binutils \
 && go install "github.com/jackc/tern/v2@${TERN_VERSION}"  \
 && strip /go/bin/tern;

# ----------------------------------------------------------------------
#  Stage 2 – minimal runtime image that still contains psql, jq, …
# ----------------------------------------------------------------------
FROM alpine:latest AS migrate

# Runtime helpers that our shell scripts already expect
RUN apk add --no-cache \
        ca-certificates bash postgresql-client curl jq openssl perl \
    && update-ca-certificates;

# Bring the statically–linked Tern binary in from the builder
COPY --from=tern-build /go/bin/tern /usr/local/bin/tern

# ----------------------------------------------------------------------
#  Build-time ARGs
# ----------------------------------------------------------------------
ARG ENV
ARG HCP_ORG_ID
ARG HCP_PROJECT_ID
ARG HCP_ENCRYPTED_API_TOKEN
ARG HCP_APP_NAME_FOR_DB_SECRETS
ARG MIGRATIONS_PATH
ARG UNIQUE_RUN_NUMBER
ARG UNIQUE_RUNNER_ID

RUN test -n "${ENV}" || ( \
  echo "Error: ENV is not set! Use --build-arg ENV=xxx" && \
  exit 1 \
);
RUN test -n "${HCP_ORG_ID}" || ( \
  echo "Error: HCP_ORG_ID is not set! Use --build-arg HCP_ORG_ID=xxx" && \
  exit 1 \
);
RUN test -n "${HCP_PROJECT_ID}" || ( \
  echo "Error: HCP_PROJECT_ID is not set! Use --build-arg HCP_PROJECT_ID=xxx" && \
  exit 1 \
);
RUN test -n "${HCP_ENCRYPTED_API_TOKEN}" || ( \
  echo "Error: HCP_ENCRYPTED_API_TOKEN is not set! Use --build-arg HCP_ENCRYPTED_API_TOKEN=xxx" && \
  exit 1 \
);
RUN test -n "${HCP_APP_NAME_FOR_DB_SECRETS}" || ( \
  echo "Error: HCP_APP_NAME_FOR_DB_SECRETS is not set! Use --build-arg HCP_APP_NAME_FOR_DB_SECRETS=xxx" && \
  exit 1 \
);
RUN test -n "${MIGRATIONS_PATH}" || ( \
  echo "Error: MIGRATIONS_PATH is not set! Use --build-arg MIGRATIONS_PATH=xxx" && \
  exit 1 \
);
RUN test -n "${UNIQUE_RUN_NUMBER}" || ( \
  echo "Error: UNIQUE_RUN_NUMBER is not set! Use --build-arg UNIQUE_RUN_NUMBER=xxx" && \
  exit 1 \
);
RUN test -n "${UNIQUE_RUNNER_ID}" || ( \
  echo "Error: UNIQUE_RUNNER_ID is not set! Use --build-arg UNIQUE_RUNNER_ID=xxx" && \
  exit 1 \
);

# ----------------------------------------------------------------------
#  Turn build-time args into env vars so the shell script can see them
# ----------------------------------------------------------------------
ENV ENV=${ENV}
ENV HCP_ORG_ID=${HCP_ORG_ID}
ENV HCP_PROJECT_ID=${HCP_PROJECT_ID}
ENV HCP_APP_NAME=${HCP_APP_NAME_FOR_DB_SECRETS}
ENV HCP_ENCRYPTED_API_TOKEN=${HCP_ENCRYPTED_API_TOKEN}
ENV MIGRATIONS_PATH=${MIGRATIONS_PATH}
ENV UNIQUE_RUN_NUMBER=${UNIQUE_RUN_NUMBER}
ENV UNIQUE_RUNNER_ID=${UNIQUE_RUNNER_ID}

# ----------------------------------------------------------------------
#  Copy migrations + helper scripts just like before
# ----------------------------------------------------------------------
WORKDIR /app
COPY ${MIGRATIONS_PATH} migrations
COPY devops-toolkit/backend/scripts/encryption.sh encryption.sh
COPY devops-toolkit/backend/scripts/fetch_launchdarkly_flag.sh fetch_launchdarkly_flag.sh
COPY devops-toolkit/shared/scripts/fetch_hcp_secret.sh fetch_hcp_secret.sh
COPY devops-toolkit/shared/scripts/fetch_hcp_secret_from_secrets_json.sh fetch_hcp_secret_from_secrets_json.sh
COPY devops-toolkit/backend/docker/scripts/migrate_cmd.sh migrate_cmd.sh

RUN chmod +x *.sh;

# ----------------------------------------------------------------------
CMD ./migrate_cmd.sh;

