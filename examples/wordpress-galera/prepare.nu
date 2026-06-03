#!/usr/bin/env nu
# Config for the experimental WordPress + Galera recipe. Same persisted DB
# credentials as the single-node WordPress recipe.
use ../../scripts/secrets.nu *

def main [] {
  let dom = ($env.DOMAIN? | default "")
  let host = ($env.WP_DOMAIN? | default (if ($dom | is-empty) { "" } else { $"wordpress.($dom)" }))
  if ($host | is-empty) {
    print -e "no domain — run 'mise run up' first, or set WP_DOMAIN=host.example.com"
    exit 1
  }
  print -e "EXPERIMENTAL: Galera needs a multi-node cluster (node_count >= 3) — see issue #2"
  {
    HOST: $host
    WP_DOMAIN: $host
    DB_USER: "wordpress"
    DB_NAME: "wordpress"
    DB_PASSWORD: (secret "VMU_WORDPRESS_DB_PASSWORD")
    DB_ROOT_PASSWORD: (secret "VMU_WORDPRESS_DB_ROOT_PASSWORD")
  } | to json
}
