#!/usr/bin/env nu
# Front non-container services (bare metal, BMC, home hubs) through the cluster's
# managed Caddy with auto-HTTPS on your domain. Prepends your snippet to the
# auto-generated Caddy config without touching uncloud-managed routes.

def main [] {
  let snippet = "caddy/external.caddyfile"
  if not ($snippet | path exists) {
    print $"ERROR: ($snippet) not found."
    print "       cp caddy/external.caddyfile.example caddy/external.caddyfile and edit it."
    print "       Reminder: hostnames must be under your domain — the wildcard *.<domain>"
    print "       record + cert already cover them, so no per-host DNS setup is needed."
    exit 1
  }
  print $"==> uc caddy deploy --caddyfile ($snippet)"
  ^uc caddy deploy --caddyfile $snippet
  print ""
  print "Merged config now serving. Inspect it with: uc caddy config"
}
