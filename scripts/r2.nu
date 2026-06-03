# R2 helpers shared by the tofu scripts.
#
# Cloudflare lets you use a CF API token AS R2 S3 credentials:
#   access key id = the token's id (32 chars), secret = sha256(token value) (64).
# So we need NO separate R2 token and store NO derived secret — we recompute it
# from CLOUDFLARE_API_TOKEN at run time. Requires the token to have R2 perms.

export const STATE_BUCKET = "vm-uncloud-tfstate"

export def r2-endpoint [] {
  $"https://($env.CLOUDFLARE_ACCOUNT_ID).r2.cloudflarestorage.com"
}

# Derive the R2 S3 credentials from the Cloudflare API token.
export def r2-derive [] {
  let tok = $env.CLOUDFLARE_API_TOKEN
  let akid = (http get -H [Authorization $"Bearer ($tok)"] "https://api.cloudflare.com/client/v4/user/tokens/verify" | get result.id)
  { AWS_ACCESS_KEY_ID: $akid, AWS_SECRET_ACCESS_KEY: ($tok | hash sha256), AWS_DEFAULT_REGION: "auto" }
}

# Creds to load before any tofu command: derived only when the remote (R2)
# backend is active, so local-state runs are untouched.
export def r2-creds [] {
  if ("tofu/backend.tf" | path exists) { r2-derive } else { {} }
}
