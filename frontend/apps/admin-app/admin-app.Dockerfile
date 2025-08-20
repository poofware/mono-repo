# -----------------------------
# Builder Stage
# -----------------------------
# Use a stable Flutter SDK image.
FROM alpine:latest AS builder

WORKDIR /app

COPY build/ /app/build/

# -----------------------------
# Runtime Stage
# -----------------------------
FROM nginx:1.27.5-alpine

# Set the port Nginx will listen on. This should match APP_PORT in your compose file.
ENV NGINX_PORT=8080

# Copy the custom Nginx configuration file.
# This file should be present in the META-SERVICE/Admin-APP/ directory.
COPY nginx.conf /etc/nginx/nginx.conf

# Copy the built static site from the builder stage to Nginx's web root.
COPY --from=builder /app/build/web /usr/share/nginx/html/admin/

# Remove Nginx's default configuration.
RUN rm -f /etc/nginx/conf.d/default.conf;

# Expose the port Nginx will run on.
EXPOSE ${NGINX_PORT}

# Command to run Nginx in the foreground.
CMD ["nginx", "-g", "daemon off;"]

