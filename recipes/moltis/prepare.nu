#!/usr/bin/env nu
# Config for the Moltis recipe. recipe.nu runs this with DOMAIN in the env.
# MOLTIS_TOKEN is persisted (scripts/secrets.nu) so the bootstrap auth is stable.
use ../../scripts/secrets.nu *

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run up' first"
    exit 1
  }
  print -e "moltis: get the first-boot setup code from 'uc logs moltis'"
  { HOST: $"moltis.($dom)", MOLTIS_TOKEN: (secret "VMU_MOLTIS_TOKEN" 40) } | to json
}
