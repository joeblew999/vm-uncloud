#!/usr/bin/env nu
# Config for the WordPress recipe. recipe.nu runs this with DOMAIN in the env.
# stdout = JSON env merged into the deploy; stderr = human notes.
# DB credentials are persisted (scripts/secrets.nu) so they stay STABLE across
# redeploys — the MariaDB volume keeps the original password.
use ../../scripts/secrets.nu *

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
    DB_PASSWORD: (secret "VMU_WORDPRESS_DB_PASSWORD")
    DB_ROOT_PASSWORD: (secret "VMU_WORDPRESS_DB_ROOT_PASSWORD")
  } | to json
}
