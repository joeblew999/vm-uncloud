#!/usr/bin/env nu
# Config for the imaginary recipe. recipe.nu runs this with DOMAIN in the env.
# stdout = JSON env merged into the deploy; stderr = the API key to use.
def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run up' first"
    exit 1
  }
  let key = ($env.IMAGINARY_API_KEY? | default (random chars --length 48))
  print -e $"imaginary API key: ($key)  — send as the 'API-Key' header (set IMAGINARY_API_KEY to pin it)"
  { HOST: $"img.($dom)", IMAGINARY_API_KEY: $key } | to json
}
