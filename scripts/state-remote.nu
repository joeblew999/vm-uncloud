#!/usr/bin/env nu
# Move tofu state into Cloudflare R2 (durable, lockable, no orphaned resources):
#   mise run state:remote
#
# Uses your CLOUDFLARE_API_TOKEN as the R2 S3 credential (token id = access key,
# sha256(token) = secret) — no separate R2 token, nothing stored. The token must
# have R2 read/write permission. Idempotent.

use r2.nu *

def main [] {
  let tok = ($env.CLOUDFLARE_API_TOKEN? | default "")
  let acct = ($env.CLOUDFLARE_ACCOUNT_ID? | default "")
  if ($tok | is-empty) or ($acct | is-empty) {
    print "ERROR: CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID must be set (fnox)."
    exit 1
  }
  let ep = (r2-endpoint)
  let creds = (r2-derive)

  print $"==> Ensuring R2 bucket ($STATE_BUCKET) exists..."
  with-env $creds {
    ^mise x aws@2.30.4 -- aws s3api create-bucket --bucket $STATE_BUCKET --endpoint-url $ep | complete | ignore
  }

  print "==> Writing tofu/backend.tf + tofu/backend.hcl"
  cp tofu/backend.tf.example tofu/backend.tf
  [ $'bucket = "($STATE_BUCKET)"'
    'key    = "vm-uncloud/terraform.tfstate"'
    'region = "auto"'
    $'endpoints = { s3 = "($ep)" }'
    'use_path_style              = true'
    'use_lockfile                = true'
    'skip_credentials_validation = true'
    'skip_region_validation      = true'
    'skip_metadata_api_check     = true'
  ] | str join "\n" | save -f tofu/backend.hcl

  print "==> tofu init -migrate-state (local -> R2)"
  with-env $creds {
    ^tofu -chdir=tofu init -migrate-state -backend-config=backend.hcl
  }
  print ""
  print "State now lives in R2. backend.tf/backend.hcl are gitignored; up/down/status"
  print "derive the R2 creds from your CF token automatically from here on."
}
