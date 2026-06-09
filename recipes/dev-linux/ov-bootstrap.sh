#!/usr/bin/env bash
# ov-bootstrap — unlock the dev/CI OrangeVault account inside the dev container so
# `fnox exec` (bitwarden provider) can resolve project secrets. Runs once at
# container start as the DEV user (called from the entrypoint), and is also on
# PATH so you can re-run it to refresh an expired session.
#
# It uses a DEDICATED dev/CI OrangeVault account (never your personal vault — see
# docs/DEVCONTAINERS.md). Credentials arrive as container env (injected by the
# recipe's prepare.nu from the operator's fnox keychain), trimmed for the uncloud
# newline quirk:
#   OV_SERVER           dev account's OrangeVault base URL (e.g. https://vault.<domain>)
#   OV_EMAIL            dev account email
#   OV_BW_CLIENTID      API key client_id   (Settings → Security → API Key)
#   OV_BW_CLIENTSECRET  API key client_secret
#   OV_MASTER_PASSWORD  dev account master password (unlocks non-interactively)
#
# On success it writes the unlock token to ~/.config/ov/session (0600) and makes
# every shell pick it up via ~/.bashrc. Only BW_SESSION (a revocable, expiring
# token) + the non-secret server/email land on disk — the API key and master
# password stay in the PID 1 env, used once here.
set -eu

trim() { printf '%s' "${1:-}" | tr -d '\r\n'; }

OV_SERVER="$(trim "${OV_SERVER:-}")"
OV_EMAIL="$(trim "${OV_EMAIL:-}")"
OV_MASTER_PASSWORD="$(trim "${OV_MASTER_PASSWORD:-}")"
export BW_CLIENTID="$(trim "${OV_BW_CLIENTID:-}")"
export BW_CLIENTSECRET="$(trim "${OV_BW_CLIENTSECRET:-}")"

if [ -z "$OV_SERVER" ] || [ -z "$OV_MASTER_PASSWORD" ] || [ -z "$BW_CLIENTID" ]; then
  echo "ov-bootstrap: OrangeVault creds not set (OV_SERVER/OV_BW_CLIENTID/OV_MASTER_PASSWORD) — skipping." >&2
  echo "ov-bootstrap: the dev container still works; secrets via fnox just won't resolve until set + redeploy." >&2
  exit 0
fi

echo "ov-bootstrap: pointing bw at $OV_SERVER" >&2
bw config server "$OV_SERVER" >/dev/null

# Log in via API key (idempotent: skip if already authenticated).
if [ "$(bw status 2>/dev/null | { grep -o '"status":"[^"]*"' || true; })" = '"status":"unauthenticated"' ] \
   || ! bw status >/dev/null 2>&1; then
  bw login --apikey >/dev/null && echo "ov-bootstrap: bw login --apikey ok" >&2
else
  echo "ov-bootstrap: already logged in" >&2
fi

# Unlock with the master password (stdin, never argv) → a session token.
BW_SESSION="$(printf '%s' "$OV_MASTER_PASSWORD" | bw unlock --raw)"
[ -n "$BW_SESSION" ] || { echo "ov-bootstrap: unlock failed" >&2; exit 1; }

# Persist for this user's shells + tasks. 0600; only the session token + non-secret
# server/email — not the API key or master password.
conf="$HOME/.config/ov"
mkdir -p "$conf"; chmod 700 "$conf"
umask 077
cat >"$conf/session" <<EOF
export BW_SESSION='$BW_SESSION'
export OV_SERVER='$OV_SERVER'
export OV_EMAIL='$OV_EMAIL'
EOF
chmod 600 "$conf/session"

# Make every login shell pick it up (idempotent).
marker='# >>> vm-uncloud orangevault session >>>'
if ! grep -qF "$marker" "$HOME/.bashrc" 2>/dev/null; then
  {
    echo ""
    echo "$marker"
    echo '[ -f "$HOME/.config/ov/session" ] && . "$HOME/.config/ov/session"'
    echo '# <<< vm-uncloud orangevault session <<<'
  } >> "$HOME/.bashrc"
fi

echo "ov-bootstrap: OrangeVault unlocked — fnox exec will resolve secrets. Refresh later with: ov-bootstrap" >&2
