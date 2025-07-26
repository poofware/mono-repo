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
FROM bitwarden/bws:latest AS bws
FROM alpine:latest AS migrate

# Runtime helpers that our shell scripts already expect
RUN apk add --no-cache \
        ca-certificates bash postgresql-client curl jq openssl perl \
    && update-ca-certificates;

COPY --from=bws /bin/bws /usr/local/bin/bws
COPY --from=bws /lib64   /lib64
COPY --from=bws /lib    /lib

# Bring the statically–linked Tern binary in from the builder
COPY --from=tern-build /go/bin/tern /usr/local/bin/tern

# ----------------------------------------------------------------------
#  Build-time ARGs
# ----------------------------------------------------------------------
ARG ENV
ARG BWS_PROJECT_NAME_FOR_DB_SECRETS
ARG UNIQUE_RUN_NUMBER
ARG UNIQUE_RUNNER_ID

RUN test -n "${ENV}" || ( \
  echo "Error: ENV is not set! Use --build-arg ENV=xxx" && \
  exit 1 \
);
RUN test -n "${BWS_PROJECT_NAME_FOR_DB_SECRETS}" || ( \
  echo "Error: BWS_PROJECT_NAME_FOR_DB_SECRETS is not set! Use --build-arg BWS_PROJECT_NAME_FOR_DB_SECRETS=xxx" && \
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
ENV BWS_PROJECT_NAME=${BWS_PROJECT_NAME_FOR_DB_SECRETS}
ENV UNIQUE_RUN_NUMBER=${UNIQUE_RUN_NUMBER}
ENV UNIQUE_RUNNER_ID=${UNIQUE_RUNNER_ID}

# ----------------------------------------------------------------------
#  Copy migrations + helper scripts just like before
# ----------------------------------------------------------------------
WORKDIR /app
COPY --from=migrations . migrations/
COPY --from=devops-toolkit backend/scripts/fetch_launchdarkly_flag.sh fetch_launchdarkly_flag.sh
COPY --from=devops-toolkit shared/scripts/fetch_bws_secret.sh fetch_bws_secret.sh
COPY --from=devops-toolkit backend/docker/scripts/migrate_cmd.sh migrate_cmd.sh

RUN chmod +x *.sh;

# ----------------------------------------------------------------------
CMD ./migrate_cmd.sh;

