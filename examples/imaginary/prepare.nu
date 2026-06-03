#!/usr/bin/env nu
# Config for the imaginary recipe. recipe.nu runs this with DOMAIN in the env.
# stdout = JSON env merged into the deploy; stderr = the API key to use.
# The API key is persisted (scripts/secrets.nu) so it's stable across deploys —
# override by setting IMAGINARY_API_KEY in your env.
use ../../scripts/secrets.nu *

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run up' first"
    exit 1
  }
  let key = ($env.IMAGINARY_API_KEY? | default (secret "VMU_IMAGINARY_API_KEY" 48))
  print -e $"imaginary API key: ($key) — send it as the 'API-Key' header"
  { HOST: $"img.($dom)", IMAGINARY_API_KEY: $key } | to json
}
