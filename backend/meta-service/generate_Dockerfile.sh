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
FROM alpine:latest AS meta-service-runner
WORKDIR /root

RUN apk add --no-cache nginx curl && mkdir -p /run/nginx;

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

COPY --from=the-website /usr/share/nginx/html/     /usr/share/nginx/html/
COPY --from=pm-app /usr/share/nginx/html/pm/ /usr/share/nginx/html/pm/

# Remove default site configs if still present
RUN rm -f /etc/nginx/conf.d/default.conf;

EXPOSE 8080
EOF

# ──────────────────────────────  Stage 5: final CMD  ──────────────────────────────
services_cmd="ulimit -n 65535 && ulimit -u 65535 && "

for svc in $SERVICES; do
  services_cmd="${services_cmd}(set -a && . /root/${svc}.env && exec /root/${svc}) & "
done

services_cmd="${services_cmd}/root/health_check & "
services_cmd="${services_cmd}nginx -g 'daemon off;'"

cat <<EOF
CMD ["/bin/sh", "-c", "${services_cmd}"]
EOF

