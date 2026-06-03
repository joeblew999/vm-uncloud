#!/usr/bin/env nu
# Move tofu state into Cloudflare R2 (durable, lockable, no orphans). One-time:
#   mise run state:remote
# Requires valid R2 S3 creds in fnox (AWS_ACCESS_KEY_ID = 32 chars,
# AWS_SECRET_ACCESS_KEY = 64 chars) and R2_ACCOUNT_ID. Idempotent.

const BUCKET = "vm-uncloud-tfstate"
const AWS = "aws@2.30.4"

def main [] {
  let ak = ($env.AWS_ACCESS_KEY_ID? | default "")
  let sk = ($env.AWS_SECRET_ACCESS_KEY? | default "")
  let acct = ($env.R2_ACCOUNT_ID? | default "")
  if ($acct | is-empty) { print "ERROR: R2_ACCOUNT_ID not set (add it to fnox.toml)."; exit 1 }
  if (($ak | str length) != 32) or (($sk | str length) != 64) {
    print $"ERROR: R2 S3 creds look wrong - access key is ($ak | str length) chars and secret is ($sk | str length) chars."
    print "       R2 needs a 32-char Access Key ID and 64-char Secret. Generate an R2 API token"
    print "       at Cloudflare -> R2 -> Manage API Tokens, then store the S3 creds in fnox."
    exit 1
  }

  let ep = $"https://($acct).r2.cloudflarestorage.com"
  print $"==> Ensuring bucket ($BUCKET) exists in R2..."
  ^mise x $AWS -- aws s3api create-bucket --bucket $BUCKET --endpoint-url $ep | complete | ignore

  print "==> Writing tofu/backend.hcl"
  [ $'bucket = "($BUCKET)"'
    'key    = "vm-uncloud/terraform.tfstate"'
    'region = "auto"'
    $'endpoints = { s3 = "($ep)" }'
    'use_path_style              = true'
    'use_lockfile                = true'
    'skip_credentials_validation = true'
    'skip_region_validation      = true'
    'skip_requester_charged      = true'
    'skip_metadata_api_check     = true'
  ] | str join "\n" | save -f tofu/backend.hcl

  cp tofu/backend.tf.example tofu/backend.tf
  print "==> tofu init -migrate-state (local -> R2)"
  ^tofu -chdir=tofu init -migrate-state -backend-config=backend.hcl
  print ""
  print "State now lives in R2. backend.tf + backend.hcl are gitignored (contain your account id)."
}
