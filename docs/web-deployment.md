# Web build and Docker image

The Flutter web build is a static site. The root `Dockerfile` builds it in a
Flutter stage and serves it with Caddy. No host reverse proxy is required on
the home server: run the container and point a Cloudflare tunnel at it. The
app bar shows `kAppVersion` so you can confirm which ship build is running
behind the tunnel.

## Run locally

From the repository root:

```sh
docker compose up --build
```

Then open <http://localhost:8099>. Override the host port or image tag if
needed:

```sh
WAFFLE_WEB_PORT=8080 docker compose up --build
WAFFLE_WEB_TAG=1.0.0 docker compose pull && docker compose up -d
```

The first build downloads the Flutter SDK (about 1.6 GB) and takes a few
minutes.

### Build notes

Flutter's Linux SDK is amd64-only, so the Dockerfile pins the build stage to
`linux/amd64`. The Caddy runtime is published for both `linux/amd64` and
`linux/arm64` so an Odroid can pull a native image.

Caddy adds an SPA fallback and sets:

- `no-cache` for `/`, `index.html`, `flutter_service_worker.js`,
  `manifest.json` and `version.json`;
- a one-hour cache for `assets/` and `canvaskit/`.

## Published image

The **Web image (GHCR)** workflow builds and smoke-tests the image, then
pushes a multi-arch manifest when:

- a GitHub Release is published, or
- you run the workflow manually with **Push the multi-arch image to GHCR**
  checked.

Tags:

- `ghcr.io/luen/glowing-waffle-web:<version>` for every push;
- `ghcr.io/luen/glowing-waffle-web:latest` when the version has no hyphen
  (stable).

The GHCR package is private by default; make it public in the package settings
if the host should pull it anonymously.

## Home server (Odroid)

```sh
mkdir -p ~/glowing-waffle && cd ~/glowing-waffle
# copy docker-compose.yml (or clone the repo), then:
docker compose pull
docker compose up -d
curl -fsS http://127.0.0.1:8099/ | head
```

Cloudflare tunnel target: `http://192.168.0.101:8099` →
`https://waffle.luenwarneke.com`. No `.env` is required for the static site.
