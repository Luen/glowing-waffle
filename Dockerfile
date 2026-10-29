# syntax=docker/dockerfile:1

# Build the Flutter web bundle and serve it with Caddy.
# The release workflow (web-image.yml) pushes a multi-arch image to GHCR;
# `docker compose up --build` builds it locally.
#
# Flutter's official Linux SDK is amd64-only, so the build stage is always
# linux/amd64. The Caddy runtime is published for amd64 and arm64 (Odroid).
# Bump FLUTTER_VERSION when the project's stable Flutter channel moves.
FROM --platform=linux/amd64 debian:bookworm-slim AS build

ARG FLUTTER_VERSION=3.47.7
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${PATH}"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      curl \
      git \
      unzip \
      xz-utils \
      zip \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      -o /tmp/flutter.tar.xz \
 && tar -xJf /tmp/flutter.tar.xz -C /opt \
 && rm /tmp/flutter.tar.xz \
 && git config --global --add safe.directory "${FLUTTER_HOME}" \
 && flutter config --no-analytics \
 && flutter precache --web

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release

FROM caddy:2-alpine
COPY --from=build /app/build/web /srv
COPY Caddyfile /etc/caddy/Caddyfile
EXPOSE 80
