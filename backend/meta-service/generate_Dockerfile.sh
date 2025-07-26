#!/usr/bin/env bash
#
# generate_Dockerfile.sh
#
# Dynamically generates a Dockerfile named "Dockerfile.generated"
# by reading your $SERVICES environment variable (e.g. "auth-service:8082 account-service:8083")
# and also adding a final CMD line that runs each sub-service plus health_check, then NGINX.

set -e

: "${SERVICES:?SERVICES env var is required}"

# ──────────────────────────────  Stage 0: boilerplate  ──────────────────────────────
cat <<'EOF'
# syntax=docker/dockerfile:1.4

##########################################################
# Stage 1: Build the small health_check binary
##########################################################
FROM golang:1.23-alpine AS health-check-builder

WORKDIR /app
COPY health_check.go .

RUN go build -o /health_check health_check.go;

#######################################
# Stage 2: Smoke Test Builder 
#######################################
FROM golang:1.23-alpine AS smoke-test-builder

ARG ENV

RUN test -n "${ENV}" || ( \
  echo "Error: ENV is not set! Use --build-arg ENV=xxx" && \
  exit 1 \
);

WORKDIR /app
COPY tests/ ./tests/
WORKDIR /app/tests

RUN ENV_TRANSFORMED=$(echo "${ENV}" | tr '-' '_') && \
    go test -c -tags "${ENV_TRANSFORMED}" -v -o /smoke_test ./smoke_test.go;

##########################################################
# Stage 3: Runner Config Validator
##########################################################
FROM alpine:latest AS runner-config-validator

ARG APP_URL_FROM_COMPOSE_NETWORK

RUN test -n "${APP_URL_FROM_COMPOSE_NETWORK}" || ( \
  echo "Error: APP_URL_FROM_COMPOSE_NETWORK is not set! Use --build-arg APP_URL_FROM_COMPOSE_NETWORK=xxx" && \
  exit 1 \
);

##########################################################
# Stage 4: Smoke Test Runner
##########################################################
FROM runner-config-validator AS smoke-test-runner

ARG APP_URL_FROM_COMPOSE_NETWORK
ENV APP_URL_FROM_COMPOSE_NETWORK=${APP_URL_FROM_COMPOSE_NETWORK}

RUN apk add --no-cache curl jq openssl bash ca-certificates && update-ca-certificates;

WORKDIR /root/
COPY --from=smoke-test-builder /smoke_test /root/smoke_test

CMD ./smoke_test -test.v
EOF

# ──────────────────────────────  Stage 2: service images  ──────────────────────────────
for svc in $SERVICES; do
  cat <<EOF

##########################################################
# Bring in the final image for $svc
##########################################################
FROM ${svc}:latest AS ${svc}
EOF
done

# ──────────────────────────────  Stage 3: website image  ──────────────────────────────
cat <<'EOF'

##########################################################
# Bring in the built website image for static assets
##########################################################
FROM the-website:latest AS the-website

##########################################################
# Bring in the built pm app image for static assets
##########################################################
FROM pm-app:latest AS pm-app
EOF

# ──────────────────────────────  Stage 4: meta runner  ──────────────────────────────
cat <<'EOF'

##########################################################
# Final stage: Single Alpine w/ NGINX
##########################################################
FROM bitwarden/bws:latest AS bws
FROM alpine:latest AS meta-service-runner
WORKDIR /root

ARG ENV
ARG SERVICES

RUN test -n "${ENV}" || ( \
  echo "Error: ENV is not set! Use --build-arg ENV=xxx" && \
  exit 1 \
);
RUN test -n "${SERVICES}" || ( \
  echo "Error: SERVICES is not set! Use --build-arg SERVICES=xxx" && \
  exit 1 \
);

ENV ENV=${ENV}
ENV SERVICES="${SERVICES}"

RUN apk add --no-cache nginx curl bash jq gettext && mkdir -p /run/nginx;
COPY --from=bws /bin/bws /usr/local/bin/bws
COPY --from=bws /lib64   /lib64
COPY --from=bws /lib     /lib

ARG APP_PORT
RUN test -n "${APP_PORT}" || ( \
  echo "Error: APP_PORT is not set! Use --build-arg APP_PORT=xxx" && \
  exit 1 \
);
ENV APP_PORT=${APP_PORT}

# Copy health_check from its builder
COPY --from=health-check-builder /health_check /root/health_check
EOF

# ──────────────────────────────  Stage 4a: copy binaries  ──────────────────────────────
for svc in $SERVICES; do
  cat <<EOF
# Copy $svc binary and env
COPY --from=${svc} /root/${svc} /root/${svc}
COPY --from=${svc} /root/.env   /root/${svc}.env

EOF
done

# ──────────────────────────────  Stage 4b: website assets & nginx config  ─────────────
cat <<'EOF'
# Copy nginx configuration and built static site from the website image
COPY nginx.conf /etc/nginx/nginx.conf

COPY nginx_cf.template /etc/nginx/templates/cf-auth.conf.template

COPY --from=the-website /usr/share/nginx/html/     /usr/share/nginx/html/
COPY --from=pm-app /usr/share/nginx/html/pm/ /usr/share/nginx/html/pm/

# Remove default site configs if still present
RUN rm -f /etc/nginx/conf.d/default.conf;

EXPOSE 8080

COPY --from=devops-toolkit backend/scripts/fetch_launchdarkly_flag.sh fetch_launchdarkly_flag.sh
COPY --from=devops-toolkit shared/scripts/fetch_bws_secret.sh fetch_bws_secret.sh
COPY meta_runner_entrypoint.sh meta_runner_entrypoint.sh
RUN chmod +x *.sh

ENTRYPOINT ./meta_runner_entrypoint.sh
EOF
