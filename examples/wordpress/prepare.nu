#!/usr/bin/env nu
# Config for the WordPress recipe. recipe.nu runs this with DOMAIN in the env.
# stdout = JSON env merged into the deploy; stderr = human notes.
def main [] {
  let dom = ($env.DOMAIN? | default "")
  let host = ($env.WP_DOMAIN? | default (if ($dom | is-empty) { "" } else { $"wordpress.($dom)" }))
  if ($host | is-empty) {
    print -e "no domain — run 'mise run up' first, or set WP_DOMAIN=host.example.com"
    exit 1
  }
  {
    HOST: $host
    WP_DOMAIN: $host
    DB_USER: "wordpress"
    DB_NAME: "wordpress"
    DB_PASSWORD: (random chars --length 24)
    DB_ROOT_PASSWORD: (random chars --length 24)
  } | to json
}
