# turso-sync — the NEW Turso engine's sync server (tursodb --sync-server).
#
# Upstream (tursodatabase/turso) publishes NO server image — only prebuilt CLI
# binaries. So we do NOT build from source; we package the pinned upstream binary
# into a slim image ("run CLIs, don't fork"). One Dockerfile, multi-arch via the
# BuildKit TARGETARCH arg (amd64 = cluster cpx22, arm64 = the cax boxes).
#
# Bump TURSO_VERSION deliberately — the engine is BETA and the on-disk / sync
# protocol can change between releases.
FROM debian:12-slim

ARG TURSO_VERSION=0.6.1
ARG TARGETARCH

RUN set -eux; \
    case "${TARGETARCH}" in \
      amd64) triple=x86_64-unknown-linux-gnu ;; \
      arm64) triple=aarch64-unknown-linux-gnu ;; \
      *) echo "unsupported TARGETARCH=${TARGETARCH}" >&2; exit 1 ;; \
    esac; \
    apt-get update; \
    apt-get install -y --no-install-recommends curl xz-utils ca-certificates; \
    url="https://github.com/tursodatabase/turso/releases/download/v${TURSO_VERSION}/turso_cli-${triple}.tar.xz"; \
    curl -fsSL -o /tmp/turso.tar.xz "${url}"; \
    tar -xf /tmp/turso.tar.xz -C /tmp; \
    install -m 0755 "/tmp/turso_cli-${triple}/tursodb" /usr/local/bin/tursodb; \
    apt-get purge -y curl xz-utils; apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/* /tmp/*; \
    /usr/local/bin/tursodb --version

# The DB file lives on a volume; the sync server listens on 8080. Args come from
# the compose `command:` so the path/port stay visible in the recipe.
ENTRYPOINT ["tursodb"]
