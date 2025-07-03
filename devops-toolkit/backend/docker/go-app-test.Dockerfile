# syntax=docker/dockerfile:1.4

ARG GO_VERSION=1.24
ARG INTEGRATION_TEST_RUNNER_BASE_IMAGE=alpine:latest

#######################################
# Stage 1: Base for building & testing
#######################################
FROM golang:${GO_VERSION}-alpine AS base

# Install any necessary packages (git, openssh, etc.)
RUN apk update && apk add --no-cache git openssh curl openssl;

# Private repos? Configure SSH known_hosts if needed
ENV GOPRIVATE=github.com/poofware/*
RUN git config --global url."git@github.com:".insteadOf "https://github.com/";

WORKDIR /go/app

RUN mkdir -p /root/.ssh && ssh-keyscan github.com >> /root/.ssh/known_hosts;

COPY go.work go.mod go.sum ./
COPY --from=shared . ../../shared/

RUN --mount=type=cache,id=gomod,target=/go/pkg/mod \
    --mount=type=ssh go mod download;

#######################################
# Stage 2: Builder Config Validator
#######################################
FROM base AS builder-config-validator

ARG APP_NAME
ARG HCP_ORG_ID
ARG HCP_PROJECT_ID
ARG LD_SERVER_CONTEXT_KEY
ARG LD_SERVER_CONTEXT_KIND
ARG UNIQUE_RUN_NUMBER
ARG UNIQUE_RUNNER_ID

# Validate the configuration
RUN test -n "${APP_NAME}" || ( \
  echo "Error: APP_NAME is not set! Use --build-arg APP_NAME=xxx" && \
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
RUN test -n "${LD_SERVER_CONTEXT_KEY}" || ( \
  echo "Error: LD_SERVER_CONTEXT_KEY is not set! Use --build-arg LD_SERVER_CONTEXT_KEY=xxx" && \
  exit 1 \
);
RUN test -n "${LD_SERVER_CONTEXT_KIND}" || ( \
  echo "Error: LD_SERVER_CONTEXT_KIND is not set! Use --build-arg LD_SERVER_CONTEXT_KIND=xxx" && \
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

#######################################
# Stage 3: Integration Test Builder 
#######################################
FROM builder-config-validator AS integration-test-builder

ARG APP_NAME
ARG ENV
ARG HCP_ORG_ID
ARG HCP_PROJECT_ID
ARG LD_SERVER_CONTEXT_KEY
ARG LD_SERVER_CONTEXT_KIND
ARG UNIQUE_RUN_NUMBER
ARG UNIQUE_RUNNER_ID

# Not in builder-config-validator stage, as this changes somewhat often, 
# and we don't want to invalidate the builder stage cache for other builders every time we change it
RUN test -n "${ENV}" || ( \
  echo "Error: ENV is not set! Use --build-arg ENV=xxx" && \
  exit 1 \
);

# Copy the files needed for building integration tests
COPY internal/ ./internal/

# Compile the integration test binary (from test/integration/)
# Transform ENV by replacing dashes (-) with underscores (_) to ensure valid Go 1.24 build tags,
# as dashes are not allowed in tag names per stricter parsing (alphanumeric and underscores only).
RUN --mount=type=cache,id=gomod,target=/go/pkg/mod \
    --mount=type=cache,id=go-build-integration-test,target=/root/.cache/go-build \
    set -euxo pipefail; \
    ENV_TRANSFORMED=$(echo "${ENV}" | tr '-' '_') && \
    go test -c -tags "${ENV_TRANSFORMED},integration" \
      -ldflags "\
        -X 'github.com/poofware/${APP_NAME}/internal/config.AppName=${APP_NAME}' \
        -X 'github.com/poofware/${APP_NAME}/internal/config.UniqueRunNumber=${UNIQUE_RUN_NUMBER}' \
        -X 'github.com/poofware/${APP_NAME}/internal/config.UniqueRunnerID=${UNIQUE_RUNNER_ID}' \
        -X 'github.com/poofware/${APP_NAME}/internal/config.LDServerContextKey=${LD_SERVER_CONTEXT_KEY}' \
        -X 'github.com/poofware/${APP_NAME}/internal/config.LDServerContextKind=${LD_SERVER_CONTEXT_KIND}' \
        -X 'github.com/poofware/go-utils.HCPOrgID=${HCP_ORG_ID}' \
        -X 'github.com/poofware/go-utils.HCPProjectID=${HCP_PROJECT_ID}'" \
      -v -o /integration_test ./internal/integration/...;

#######################################
# Stage 4: Unit Test Builder 
#######################################
FROM base AS unit-test-builder

# Copy the test files for building
COPY internal/ ./internal/

# Compile the unit test binary (from internal/)
RUN --mount=type=cache,id=gomod,target=/go/pkg/mod \
    --mount=type=cache,id=go-build-unit-test,target=/root/.cache/go-build \
    go test -c -o /unit_test ./internal/...;

#######################################
# Stage 5: Integration Test Runner
#######################################
FROM ${INTEGRATION_TEST_RUNNER_BASE_IMAGE} AS integration-test-runner

RUN apk update && apk add --no-cache curl jq openssl bash ca-certificates && update-ca-certificates;

ARG ENV
ARG LOG_LEVEL
ARG APP_PORT
ARG APP_URL_FROM_COMPOSE_NETWORK
ARG APP_URL_FROM_ANYWHERE
ARG HCP_ENCRYPTED_API_TOKEN
 
RUN test -n "${ENV}" || ( \
  echo "Error: ENV is not set! Use --build-arg ENV=xxx" && \
  exit 1 \
);
RUN test -n "${LOG_LEVEL}" || ( \
  echo "Error: LOG_LEVEL is not set! Use --build-arg LOG_LEVEL=xxx" && \
  exit 1 \
);
RUN test -n "${APP_PORT}" || ( \
  echo "Error: APP_PORT is not set! Use --build-arg APP_PORT=xxx" && \
  exit 1 \
);
RUN test -n "${APP_URL_FROM_COMPOSE_NETWORK}" || ( \
  echo "Error: APP_URL_FROM_COMPOSE_NETWORK is not set! Use --build-arg APP_URL_FROM_COMPOSE_NETWORK=xxx" && \
  exit 1 \
);
RUN test -n "${APP_URL_FROM_ANYWHERE}" || ( \
  echo "Error: APP_URL_FROM_ANYWHERE is not set! Use --build-arg APP_URL_FROM_ANYWHERE=xxx" && \
  exit 1 \
);
RUN test -n "${HCP_ENCRYPTED_API_TOKEN}" || ( \
  echo "Error: HCP_ENCRYPTED_API_TOKEN is not set! Use --build-arg HCP_ENCRYPTED_API_TOKEN=xxx" && \
  exit 1 \
);

WORKDIR /root/
COPY --from=integration-test-builder /integration_test ./integration_test
COPY --from=devops-toolkit backend/docker/scripts/integration_test_runner_cmd.sh integration_test_runner_cmd.sh

RUN chmod +x integration_test_runner_cmd.sh;

# Convert ARG to ENV for runtime use
ENV ENV=${ENV}
ENV LOG_LEVEL=${LOG_LEVEL}
ENV APP_PORT=${APP_PORT}
ENV APP_URL_FROM_COMPOSE_NETWORK=${APP_URL_FROM_COMPOSE_NETWORK}
ENV APP_URL_FROM_ANYWHERE=${APP_URL_FROM_ANYWHERE}
ENV HCP_ENCRYPTED_API_TOKEN=${HCP_ENCRYPTED_API_TOKEN}

CMD ./integration_test_runner_cmd.sh;

#######################################
# Stage 6: Unit Test Runner
#######################################
FROM alpine:latest AS unit-test-runner

ARG LOG_LEVEL

RUN test -n "${LOG_LEVEL}" || ( \
  echo "Error: LOG_LEVEL is not set! Use --build-arg LOG_LEVEL=xxx" && \
  exit 1 \
);

WORKDIR /root/
COPY --from=unit-test-builder /unit_test ./unit_test

ENV LOG_LEVEL=${LOG_LEVEL}

CMD ./unit_test -test.v;
