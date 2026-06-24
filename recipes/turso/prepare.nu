#!/usr/bin/env nu
# Config for the Turso/libSQL recipe. recipe.nu runs this with DOMAIN in the env
# and merges the JSON it prints on stdout into the deploy env; stderr is notes.
#
# It wires sqld's "bottomless" WAL backup to R2, reusing the SAME credential
# derivation as the tofu state backend (scripts/r2.nu: the CF API token IS the R2
# S3 credential — token id = access key, sha256(token) = secret). No new secret.
#
# Policy: backup is ON by default and this REFUSES to deploy without R2 — robust
# means never running the production DB without a backup target. Two ways off
# that path, both deliberate:
#   - local dev   (VMU_SECRET_DRY=1, set by `mise run recipe:local`) -> backup off
#   - explicit    (TURSO_BACKUP=off) -> backup off, with a loud warning
use ../../scripts/r2.nu *
use auth.nu *

def main [] {
  let dry = (($env.VMU_SECRET_DRY? | default "") == "1")
  let want = ((($env.TURSO_BACKUP? | default "on") | str downcase) != "off")
  let bucket = ($env.TURSO_BUCKET? | default "vm-uncloud-turso")
  let domain = ($env.DOMAIN? | default "")

  # Disabled path: local dev or explicit opt-out. Emit explicit "false" + empty
  # creds (never empty ENABLED — empty would wrongly turn backup ON in sqld).
  # Empty TURSO_JWT_PUBKEY = no auth (fine for local dev only).
  if $dry or (not $want) {
    if (not $dry) {
      print -e "⚠ TURSO_BACKUP=off — sqld runs WITHOUT off-box backup. A box loss loses all data."
    } else {
      print -e "turso (local): backup + auth disabled (ephemeral dev data)."
    }
    return ({
      TURSO_BACKUP_ENABLED: "false"
      TURSO_BUCKET: "" TURSO_ENDPOINT: "" TURSO_AKID: "" TURSO_SECRET: ""
      TURSO_REGION: "" TURSO_DB_ID: "vmu-turso" TURSO_JWT_PUBKEY: ""
    } | to json)
  }

  # Enabled path: require the R2 inputs, then derive the S3 creds.
  let acct = ($env.CLOUDFLARE_ACCOUNT_ID? | default "")
  let tok  = ($env.CLOUDFLARE_API_TOKEN? | default "")
  if ($acct | is-empty) or ($tok | is-empty) {
    print -e "ERROR: Turso backup needs R2 — set CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN"
    print -e "       (mise run secrets:set). Or run with TURSO_BACKUP=off to skip backup."
    exit 1
  }

  let creds = (r2-derive)          # { AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION }
  let endpoint = (r2-endpoint)
  # JWT auth: get-or-create the Ed25519 keypair (persisted in the keychain) and
  # publish the public key so every request needs a token. `turso:token` prints
  # the client token. This is why exposing db.<domain> publicly is safe.
  let keys = (ensure-keys)

  print -e $"turso: bottomless backup -> ($endpoint)/($bucket)  [db-id vmu-turso]"
  print -e $"  the R2 bucket '($bucket)' must exist \(create it in the CF dashboard, like vm-uncloud-tfstate)."
  print -e "  restore is automatic: a fresh sqld with an empty volume pulls the latest generation."
  print -e "  JWT auth ON — clients need a token: mise run turso:token"

  ({
    TURSO_BACKUP_ENABLED: "true"
    TURSO_BUCKET: $bucket
    TURSO_ENDPOINT: $endpoint
    TURSO_AKID: $creds.AWS_ACCESS_KEY_ID
    TURSO_SECRET: $creds.AWS_SECRET_ACCESS_KEY
    TURSO_REGION: $creds.AWS_DEFAULT_REGION
    TURSO_DB_ID: "vmu-turso"
    TURSO_JWT_PUBKEY: $keys.pub
    HOST: $"db.($domain)"
  } | to json)
}
