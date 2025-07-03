# ────────────────────────────────  Builder  ────────────────────────────────
FROM node:24.3.0-alpine AS builder
WORKDIR /app

# install only the tools we need
COPY package*.json vite.config.js ./
RUN npm ci;

# bring in the raw source and build
COPY src ./src
RUN npm run build;

# ────────────────────────────────  Runtime  ───────────────────────────────
FROM nginx:1.27.5-alpine

# Environment
ENV NGINX_PORT=8080

# Custom config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy the built static site
COPY --from=builder /app/dist/ /usr/share/nginx/html/

# Remove default site configs
RUN rm -f /etc/nginx/conf.d/default.conf;

EXPOSE ${NGINX_PORT}
CMD ["nginx", "-g", "daemon off;"]

