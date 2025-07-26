# syntax=docker/dockerfile:1.4

ARG STRIPE_CLI_VERSION=1.25.1

#######################################
# Stage 1: Runner Config Validator
#######################################
FROM bitwarden/bws:latest AS bws
FROM stripe/stripe-cli:v${STRIPE_CLI_VERSION} AS runner-config-validator

RUN apk update \
 && apk add --no-cache \
      bash \
      curl \
      jq \
      openssl \
      ca-certificates;

COPY --from=bws /bin/bws /usr/local/bin/bws
COPY --from=bws /lib64   /lib64
COPY --from=bws /lib    /lib

ARG APP_NAME
ARG ENV

# Validate build-args that we'll rely on at runtime
RUN test -n "${APP_NAME}" || ( \
  echo "Error: APP_NAME is not set! Use --build-arg APP_NAME=xxx" && \
  exit 1 \
);
RUN test -n "${ENV}" || ( \
  echo "Error: ENV is not set! Use --build-arg ENV=xxx" && \
  exit 1 \
);

ENV APP_NAME=${APP_NAME}
ENV ENV=${ENV}

USER root
WORKDIR /root/

COPY --from=devops-toolkit shared/scripts/fetch_bws_secret.sh fetch_bws_secret.sh

RUN chmod +x *.sh;

#######################################
# Stage 2: Stripe Webhook Check Runner
#######################################
FROM runner-config-validator AS stripe-webhook-check-runner

ARG APP_NAME
ARG ENV
ARG APP_URL_FROM_ANYWHERE
ARG STRIPE_WEBHOOK_CHECK_ROUTE
ARG UNIQUE_RUN_NUMBER
ARG UNIQUE_RUNNER_ID

ENV APP_NAME=${APP_NAME}
ENV APP_URL_FROM_ANYWHERE=${APP_URL_FROM_ANYWHERE}
ENV STRIPE_WEBHOOK_CHECK_ROUTE=${STRIPE_WEBHOOK_CHECK_ROUTE}
ENV UNIQUE_RUN_NUMBER=${UNIQUE_RUN_NUMBER}
ENV UNIQUE_RUNNER_ID=${UNIQUE_RUNNER_ID}
ENV BWS_PROJECT_NAME=shared-${ENV}

RUN test -n "${APP_URL_FROM_ANYWHERE}" || ( \
  echo "Error: APP_URL_FROM_ANYWHERE is not set! Use --build-arg APP_URL_FROM_ANYWHERE=xxx" && \
  exit 1 \
);
RUN test -n "${STRIPE_WEBHOOK_CHECK_ROUTE}" || ( \
  echo "Error: STRIPE_WEBHOOK_CHECK_ROUTE is not set! Use --build-arg STRIPE_WEBHOOK_CHECK_ROUTE=xxx" && \
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

COPY --from=devops-toolkit backend/scripts/health_check.sh health_check.sh
COPY --from=devops-toolkit backend/docker/scripts/stripe_webhook_check_runner_entrypoint.sh stripe_webhook_check_runner_entrypoint.sh
  
RUN chmod +x health_check.sh stripe_webhook_check_runner_entrypoint.sh;
  
ENTRYPOINT ./stripe_webhook_check_runner_entrypoint.sh; 
   
#######################################
# Stage 3: Stripe Listener Runner
#######################################
FROM runner-config-validator AS stripe-listener-runner

ARG APP_NAME
ARG ENV
ARG STRIPE_WEBHOOK_CONNECTED_EVENTS
ARG STRIPE_WEBHOOK_PLATFORM_EVENTS
ARG STRIPE_WEBHOOK_ROUTE
ARG APP_URL_FROM_COMPOSE_NETWORK

RUN test -n "${STRIPE_WEBHOOK_ROUTE}" || ( \
  echo "Error: STRIPE_WEBHOOK_ROUTE is not set! Use --build-arg STRIPE_WEBHOOK_ROUTE=xxx" && \
  exit 1 \
);
RUN test -n "${APP_URL_FROM_COMPOSE_NETWORK}" || ( \
  echo "Error: APP_URL_FROM_COMPOSE_NETWORK is not set! Use --build-arg APP_URL_FROM_COMPOSE_NETWORK=xxx" && \
  exit 1 \
);

ENV STRIPE_WEBHOOK_CONNECTED_EVENTS="${STRIPE_WEBHOOK_CONNECTED_EVENTS}"
ENV STRIPE_WEBHOOK_PLATFORM_EVENTS="${STRIPE_WEBHOOK_PLATFORM_EVENTS}"
ENV STRIPE_WEBHOOK_ROUTE=${STRIPE_WEBHOOK_ROUTE}
ENV APP_URL_FROM_COMPOSE_NETWORK=${APP_URL_FROM_COMPOSE_NETWORK}
ENV BWS_PROJECT_NAME_FOR_STRIPE_SECRET=shared-${ENV}
ENV BWS_PROJECT_NAME_FOR_ENABLE_LISTENER=${APP_NAME}-${ENV}

COPY --from=devops-toolkit backend/scripts/fetch_launchdarkly_flag.sh fetch_launchdarkly_flag.sh
COPY --from=devops-toolkit backend/docker/scripts/stripe_listener_runner_entrypoint.sh stripe_listener_runner_entrypoint.sh

RUN chmod +x *.sh;

ENTRYPOINT ./stripe_listener_runner_entrypoint.sh
