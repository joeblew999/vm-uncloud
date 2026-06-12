#!/usr/bin/env nu
# Config for the Rauthy recipe. recipe.nu runs this with DOMAIN in the env and
# injects the returned JSON as env into compose.yaml.
#
# Every generated value goes through the persisting `secret`/`secret-b64`
# helpers so they're STABLE across redeploys. This is load-bearing for Rauthy:
#   - ENC_KEYS encrypts data at rest → a new key orphans existing data.
#   - HQL_SECRET_* gate the Hiqlite Raft/API → must not churn.
# The signing keys themselves live in the rauthy_data volume — don't wipe it.
use ../../scripts/secrets.nu *

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run up' first"
    exit 1
  }

  # Rauthy ENC_KEYS format: "<keyId>/<base64-32-byte-key>". The id is a short
  # stable label (matches Rauthy's 16-char examples); ENC_KEY_ACTIVE names it.
  let enc_id = (secret "VMU_RAUTHY_ENC_KEY_ID" 16)
  let enc_key = (secret-b64 "VMU_RAUTHY_ENC_KEY" 32)

  print -e $"rauthy: admin login at https://id.($dom) — first-boot password is the persisted BOOTSTRAP value below \(or 'uc logs rauthy' on the very first start\)"
  print -e "rauthy: VERIFY the discovery issuer is https BEFORE wiring the Worker:"
  print -e $"        curl -s https://id.($dom)/auth/v1/.well-known/openid-configuration | jq .issuer"
  print -e "rauthy: then register an OIDC client for the Worker (redirect = https://<worker-domain>/oauth/callback)"

  {
    HOST: $"id.($dom)",
    RAUTHY_ADMIN_EMAIL: $"admin@($dom)",
    RAUTHY_ADMIN_PASSWORD: (secret "VMU_RAUTHY_ADMIN_PASSWORD" 40),
    ENC_KEY_ACTIVE: $enc_id,
    ENC_KEYS: $"($enc_id)/($enc_key)",
    HQL_SECRET_RAFT: (secret "VMU_RAUTHY_HQL_RAFT" 48),
    HQL_SECRET_API: (secret "VMU_RAUTHY_HQL_API" 48)
  } | to json
}
