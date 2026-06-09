#!/usr/bin/env bash
# dev-linux entrypoint: authorize the developer's SSH key, fix ownership of the
# workspace + mounted Docker socket, then run sshd in the foreground as PID 1.
#
# uncloud appends a trailing newline to every injected env value (see the repo
# gotchas), so exact-match values are trimmed here before use.
set -eu

DEV_USER="$(printf '%s' "${DEV_USER:-vscode}" | tr -d '\r\n')"
PUBKEY="$(printf '%s' "${SSH_PUBKEY:-}" | tr -d '\r')"

HOME_DIR="$(getent passwd "$DEV_USER" | cut -d: -f6)"
HOME_DIR="${HOME_DIR:-/home/$DEV_USER}"

install -d -m 700 -o "$DEV_USER" -g "$DEV_USER" "$HOME_DIR/.ssh"
if [ -n "$(printf '%s' "$PUBKEY" | tr -d '[:space:]')" ]; then
  printf '%s\n' "$PUBKEY" >"$HOME_DIR/.ssh/authorized_keys"
  chown "$DEV_USER:$DEV_USER" "$HOME_DIR/.ssh/authorized_keys"
  chmod 600 "$HOME_DIR/.ssh/authorized_keys"
else
  echo "dev-linux: WARNING no SSH_PUBKEY set — nobody can SSH in. Set DEV_SSH_PUBKEY and redeploy." >&2
fi

# Workspace volume: owned by the dev user and their default login directory, so
# `ssh dev@host` and VS Code Remote-SSH land in /workspace.
install -d -o "$DEV_USER" -g "$DEV_USER" /workspace
usermod -d /workspace "$DEV_USER" 2>/dev/null || true

# Reconcile the mounted host Docker socket's group so the dev user can use it
# (its GID differs per node). Best-effort — the project's `mise run docker` task
# needs it; a dev that doesn't build images is unaffected.
if [ -S /var/run/docker.sock ]; then
  SOCK_GID="$(stat -c %g /var/run/docker.sock)"
  if [ "$SOCK_GID" != "0" ]; then
    if getent group "$SOCK_GID" >/dev/null 2>&1; then
      usermod -aG "$(getent group "$SOCK_GID" | cut -d: -f1)" "$DEV_USER" 2>/dev/null || true
    else
      groupmod -g "$SOCK_GID" docker 2>/dev/null || true
    fi
  fi
fi

# Unlock the dedicated dev/CI OrangeVault account (if its creds were injected) so
# `fnox exec` resolves project secrets inside the container. Runs as the dev user;
# non-fatal — the container is fully usable without it. See ov-bootstrap +
# docs/DEVCONTAINERS.md. `su -p` preserves the injected OV_*/BW_* env.
if command -v ov-bootstrap >/dev/null 2>&1; then
  su -p "$DEV_USER" -s /bin/bash -c 'ov-bootstrap || true' || true
fi

# Keys only — no password auth.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
ssh-keygen -A
echo "dev-linux: sshd up on :22 (published via x-ports <port>:22@host); login as '$DEV_USER' into /workspace" >&2
exec /usr/sbin/sshd -D -e
