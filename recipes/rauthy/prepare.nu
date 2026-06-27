#!/usr/bin/env nu
# Config for the Rauthy recipe. recipe.nu runs this with DOMAIN in the env and
# injects the returned JSON as env into compose.yaml.
#
# Every generated value goes through the persisting `secret`/`secret-b64`
# helpers so they're STABLE across redeploys. This is load-bearing for Rauthy:
#   - ENC_KEYS encrypts data at rest → a new key orphans existing data.
#   - HQL_SECRET_* gate the Hiqlite Raft/API → must not churn.
#   - per-client secrets must stay stable or consumers can't authenticate.
# The signing keys themselves live in the rauthy_data volume — don't wipe it.
#
# Per-project AuthN (clients/roles/groups) is declared in bootstrap.nuon; this
# turns it into Rauthy's bootstrap JSON (BOOTSTRAP_* env, seeded by the recipe's
# init container into BOOTSTRAP_DIR) with generated, persisted client secrets.
use ../../scripts/secrets.nu *

# Build one Rauthy bootstrap client (clients.json shape) from a bootstrap.nuon
# entry, generating + persisting its 64-char secret (exactly 64 — Rauthy
# validates with constant_time_eq_64; longer stores but never matches).
def build-client [c] {
  let sec = (secret $"VMU_RAUTHY_CLIENT_($c.id)" 64)
  {
    client: {
      id: $c.id,
      name: ($c.name? | default $c.id),
      secret: { Plain: $sec },
      redirect_uris: ($c.redirect_uris? | default []),
      enabled: true,
      flows_enabled: ($c.flows? | default ["authorization_code"]),
      access_token_alg: "EdDSA",
      id_token_alg: "EdDSA",
      auth_code_lifetime: 60,
      access_token_lifetime: 3600,
      scopes: ($c.scopes? | default ["openid"]),
      default_scopes: ($c.scopes? | default ["openid"]),
      force_mfa: false
    },
    note: $"client '($c.id)' secret: ($sec)"
  }
}

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run cluster:up' first"
    exit 1
  }

  # Rauthy ENC_KEYS format: "<keyId>/<base64-32-byte-key>". The id is a short
  # stable label (matches Rauthy's 16-char examples); ENC_KEY_ACTIVE names it.
  let enc_id = (secret "VMU_RAUTHY_ENC_KEY_ID" 16)
  let enc_key = (secret-b64 "VMU_RAUTHY_ENC_KEY" 32)

  # ── Declarative bootstrap (clients/roles/groups) ─────────────────────────
  let bs_file = $"($env.FILE_PWD)/bootstrap.nuon"
  mut clients_json = ""
  mut roles_json = ""
  mut groups_json = ""
  # Email defaults (overridden by bootstrap.nuon's `email` block). The webhook
  # placeholder is a no-op target so smtp2http still starts when email is unset.
  mut email_webhook = "http://localhost:9/disabled"
  mut smtp_from = $"Rauthy <noreply@($dom)>"
  if ($bs_file | path exists) {
    let bs = (open $bs_file)
    let built = ($bs.clients? | default [] | each {|c| build-client $c })
    if ($built | is-not-empty) {
      $clients_json = ($built | get client | to json -r)
      for n in ($built | get note) { print -e $"rauthy bootstrap: ($n)" }
    }
    let roles = ($bs.roles? | default [] | each {|r| { name: $r }})
    if ($roles | is-not-empty) { $roles_json = ($roles | to json -r) }
    let groups = ($bs.groups? | default [] | each {|g| { name: $g }})
    if ($groups | is-not-empty) { $groups_json = ($groups | to json -r) }
    if (($bs.email?.webhook? | default "") != "") { $email_webhook = $bs.email.webhook }
    if (($bs.email?.from? | default "") != "") { $smtp_from = $bs.email.from }
  }

  print -e $"rauthy: admin login at https://id.($dom) — first-boot password is the persisted BOOTSTRAP value below \(or 'uc logs rauthy' on the very first start\)"
  print -e "rauthy: VERIFY the discovery issuer is https BEFORE wiring the Worker:"
  print -e $"        curl -s https://id.($dom)/auth/v1/.well-known/openid-configuration | jq .issuer"

  {
    HOST: $"id.($dom)",
    RAUTHY_ADMIN_EMAIL: $"admin@($dom)",
    RAUTHY_ADMIN_PASSWORD: (secret "VMU_RAUTHY_ADMIN_PASSWORD" 40),
    ENC_KEY_ACTIVE: $enc_id,
    ENC_KEYS: $"($enc_id)/($enc_key)",
    HQL_SECRET_RAFT: (secret "VMU_RAUTHY_HQL_RAFT" 48),
    HQL_SECRET_API: (secret "VMU_RAUTHY_HQL_API" 48),
    BOOTSTRAP_CLIENTS: $clients_json,
    BOOTSTRAP_ROLES: $roles_json,
    BOOTSTRAP_GROUPS: $groups_json,
    RAUTHY_EMAIL_WEBHOOK: $email_webhook,
    RAUTHY_SMTP_FROM: $smtp_from
  } | to json
}
