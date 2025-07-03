# syntax=docker/dockerfile:1.4

ARG GO_VERSION=1.24

#######################################
# Stage 1: Base for building & testing
#######################################
FROM golang:${GO_VERSION}-alpine AS base

# Install any necessary packages (git, openssh, etc.)
RUN apk update && apk add --no-cache git openssh curl openssl;

# Private repos? Configure SSH known_hosts if needed
ENV GOPRIVATE=github.com/poofware/*
RUN git config --global url."git@github.com:".insteadOf "https://github.com/";

WORKDIR /app

RUN mkdir -p /root/.ssh && ssh-keyscan github.com >> /root/.ssh/known_hosts;

# Copy mod files and vendor
COPY go.mod go.sum ./
COPY vendor/ ./vendor/

# This is the key preparation step.
# If vendor/ is empty, we download modules to the cache AND remove the empty
# vendor/ directory. This prevents Go from failing on an inconsistent state.
# If vendor/ is populated, we do nothing, preparing for a vendor-based build.
RUN --mount=type=cache,id=gomod,target=/go/pkg/mod \
    --mount=type=ssh \
    if [ -z "$(ls -A vendor 2>/dev/null)" ]; then \
      echo "Vendor directory is empty, populating module cache and removing vendor dir..." ; \
      go mod download; \
      rm -rf vendor; \
    else \
      echo "Vendor directory is populated, skipping module download." ; \
    fi;

#######################################
# Stage 2: Builder Config Validator
#######################################
FROM base AS builder-config-validator

ARG APP_NAME
ARG HCP_ORG_ID
ARG HCP_PROJECT_ID
ARG LD_SERVER_CONTEXT_KEY
ARG LD_SERVER_CONTEXT_KIND

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

#######################################
# Stage 3: App Build Runner (compile app)
#######################################
FROM builder-config-validator AS app-builder

ARG APP_NAME
ARG HCP_ORG_ID
ARG HCP_PROJECT_ID
ARG LD_SERVER_CONTEXT_KEY
ARG LD_SERVER_CONTEXT_KIND
ARG UNIQUE_RUN_NUMBER
ARG UNIQUE_RUNNER_ID

RUN test -n "${UNIQUE_RUN_NUMBER}" || ( \
  echo "Error: UNIQUE_RUN_NUMBER is not set! Use --build-arg UNIQUE_RUN_NUMBER=xxx" && \
  exit 1 \
);
RUN test -n "${UNIQUE_RUNNER_ID}" || ( \
  echo "Error: UNIQUE_RUNNER_ID is not set! Use --build-arg UNIQUE_RUNNER_ID=xxx" && \
  exit 1 \
);

# Copy the entire source for building
COPY internal/ ./internal/
COPY cmd/ ./cmd/

# A single, clean build command. Go's implicit logic will automatically
# use the vendor directory if it exists and is non-empty, otherwise it will
# use the module cache (since we removed the empty vendor directory in the base stage).
RUN --mount=type=cache,id=gomod,target=/go/pkg/mod \
    --mount=type=cache,id=go-build-app,target=/root/.cache/go-build \
    go build \
      -ldflags "\
        -X 'github.com/poofware/${APP_NAME}/internal/config.AppName=${APP_NAME}' \
        -X 'github.com/poofware/${APP_NAME}/internal/config.UniqueRunNumber=${UNIQUE_RUN_NUMBER}' \
        -X 'github.com/poofware/${APP_NAME}/internal/config.UniqueRunnerID=${UNIQUE_RUNNER_ID}' \
        -X 'github.com/poofware/${APP_NAME}/internal/config.LDServerContextKey=${LD_SERVER_CONTEXT_KEY}' \
        -X 'github.com/poofware/${APP_NAME}/internal/config.LDServerContextKind=${LD_SERVER_CONTEXT_KIND}' \
        -X 'github.com/poofware/go-utils.HCPOrgID=${HCP_ORG_ID}' \
        -X 'github.com/poofware/go-utils.HCPProjectID=${HCP_PROJECT_ID}'" \
      -v -o "/${APP_NAME}" ./cmd/main.go;

######################################
# Stage 4: Health Check Runner
######################################

FROM alpine:latest AS health-check-runner

RUN apk add --no-cache curl bash;

ARG APP_URL_FROM_ANYWHERE

RUN test -n "${APP_URL_FROM_ANYWHERE}" || ( \
  echo "Error: APP_URL_FROM_ANYWHERE is not set! Use --build-arg APP_URL_FROM_ANYWHERE=xxx" && \
  exit 1 \
);

ENV APP_URL_FROM_ANYWHERE=${APP_URL_FROM_ANYWHERE}

WORKDIR /root/
COPY devops-toolkit/backend/scripts/health_check.sh health_check.sh

CMD ./health_check.sh;

#######################################
# Stage 5: Minimal Final App Image
#######################################
FROM alpine:latest AS app-runner

RUN apk add --no-cache curl;

ARG APP_NAME
ARG APP_PORT
ARG APP_URL_FROM_ANYWHERE
ARG LOG_LEVEL
ARG ENV
ARG HCP_ENCRYPTED_API_TOKEN

# TODO: Clean this up later, figure out best way to validate all args
RUN test -n "${APP_PORT}" || ( \
  echo "Error: APP_PORT is not set! Use --build-arg APP_PORT=xxx" && \
  exit 1 \
);
RUN test -n "${ENV}" || ( \
  echo "Error: ENV is not set! Use --build-arg ENV=xxx" && \
  exit 1 \
);
RUN test -n "${APP_URL_FROM_ANYWHERE}" || ( \
  echo "Error: APP_URL_FROM_ANYWHERE is not set! Use --build-arg APP_URL_FROM_ANYWHERE=xxx" && \
  exit 1 \
);
RUN test -n "${LOG_LEVEL}" || ( \
  echo "Error: LOG_LEVEL is not set! Use --build-arg LOG_LEVEL=xxx" && \
  exit 1 \
);
RUN test -n "${HCP_ENCRYPTED_API_TOKEN}" || ( \
  echo "Error: HCP_ENCRYPTED_API_TOKEN is not set! Use --build-arg HCP_ENCRYPTED_API_TOKEN=xxx" && \
  exit 1 \
);

WORKDIR /root/
COPY --from=app-builder /${APP_NAME} ./${APP_NAME}

EXPOSE ${APP_PORT}

# Convert ARG to ENV for runtime use with CMD
ENV APP_NAME=${APP_NAME}
ENV APP_PORT=${APP_PORT}
ENV APP_URL_FROM_ANYWHERE=${APP_URL_FROM_ANYWHERE}
ENV LOG_LEVEL=${LOG_LEVEL}
ENV ENV=${ENV}
ENV HCP_ENCRYPTED_API_TOKEN=${HCP_ENCRYPTED_API_TOKEN}

# Copy all envs into a .env file for potential children images to access
RUN echo "APP_NAME=${APP_NAME}" > .env && \
    echo "APP_PORT=${APP_PORT}" >> .env && \
    echo "APP_URL_FROM_ANYWHERE=${APP_URL_FROM_ANYWHERE}" >> .env && \
    echo "LOG_LEVEL=${LOG_LEVEL}" >> .env && \
    echo "ENV=${ENV}" >> .env && \
    echo "HCP_ENCRYPTED_API_TOKEN=${HCP_ENCRYPTED_API_TOKEN}" >> .env;

CMD ./$APP_NAME

