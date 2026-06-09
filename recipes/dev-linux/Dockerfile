# dev-linux — a remote Linux dev container, deployed as an uncloud recipe.
#
# Built on the Dev Containers base image (so VS Code's "Dev Containers" /
# Remote-SSH tooling feels at home) + mise. Specific language toolchains are NOT
# baked here: each developer project pins its own in mise.toml, and `mise`
# installs them on the first `mise run` after the repo is synced in. We bake only
# the universal prerequisites: a C toolchain + headers (most Rust crates need
# them to link), git, the Docker CLI (the project's `mise run docker` task builds
# against the mounted host socket), rsync (workspace sync), and openssh-server
# (the entry point for Remote-SSH / `devcontainer exec` / rsync).
FROM mcr.microsoft.com/devcontainers/base:ubuntu

ARG DEV_USER=vscode

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      build-essential pkg-config libssl-dev ca-certificates curl git rsync \
      openssh-server docker.io \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/run/sshd

# mise, system-wide, on PATH for login + non-login + sshd sessions. Each project
# drives its own toolchain via `mise`; gh (for the release task) installs as a
# mise tool on first use, so it isn't baked.
RUN curl -fsSL https://mise.run | MISE_INSTALL_PATH=/usr/local/bin/mise sh \
    && echo 'eval "$(/usr/local/bin/mise activate bash)"' >> /etc/bash.bashrc \
    && ln -sf /usr/local/bin/mise /usr/bin/mise

# Let the dev user reach the mounted Docker socket (the entrypoint reconciles the
# host socket's GID at runtime, since it varies per node).
RUN groupadd -f docker && usermod -aG docker "${DEV_USER}"

COPY entrypoint.sh /usr/local/bin/dev-entrypoint.sh
RUN chmod +x /usr/local/bin/dev-entrypoint.sh

EXPOSE 22
ENTRYPOINT ["/usr/local/bin/dev-entrypoint.sh"]
