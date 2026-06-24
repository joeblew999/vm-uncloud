#!/usr/bin/env nu
# Deploy services from compose.yaml to the cluster.
#
# Injects DOMAIN from the cluster's single source of truth (tofu/terraform.tfvars,
# read via tofu state) so compose files use ${DOMAIN} instead of a hardcoded host.
# `uncloud deploy` also builds any `build:` services locally and pushes them.

use r2.nu *
use cluster.nu *

def main [] {
  load-env (r2-creds)   # so tofu output can read remote state
  if not ("compose.yaml" | path exists) {
    print "ERROR: compose.yaml not found in the repo root."
    exit 1
  }
  let dom = (cluster-domain)
  let envs = (if ($dom | is-empty) { {} } else { { DOMAIN: $dom } })
  if ($dom | is-not-empty) { print $"==> DOMAIN=($dom)" }
  print "==> uncloud deploy -f compose.yaml"
  with-env $envs { ^uncloud deploy -f compose.yaml }
  print ""
  print "Deployed. Check status with: mise run status"
}
