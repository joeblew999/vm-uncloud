#!/usr/bin/env nu
# CI/verification check: provision a throwaway Hetzner box and immediately
# destroy it. Infra only — no DNS, no uncloud — so it runs headless (no TTY)
# and costs a fraction of a cent. Proves the OpenTofu apply/destroy path.

use r2.nu *

const TOFU = ["-chdir=tofu"]
# Override only the throwaway bits; ssh_key_name (and server_type/location) come
# from terraform.tfvars — nothing user-specific hardcoded here.
const VARS = ["-var=cluster_name=uncloud-smoke" "-var=node_count=1"
              "-var=domain=" "-var=cloudflare_zone_id="]

def main [] {
  load-env (r2-creds)   # R2 state creds (no-op for local state)
  if not ("tofu/terraform.tfvars" | path exists) {
    print "ERROR: tofu/terraform.tfvars not found (needed for ssh_key_name)."
    exit 1
  }
  print "==> tofu init"
  ^tofu ...$TOFU init -input=false
  print "==> tofu apply (throwaway box, no DNS)"
  ^tofu ...$TOFU apply -auto-approve -input=false ...$VARS
  let ip = (^tofu ...$TOFU output -raw ingress_ipv4)
  print $"==> Provisioned ($ip). Destroying..."
  ^tofu ...$TOFU destroy -auto-approve -input=false ...$VARS
  print "==> Smoke test passed: apply + destroy clean."
}
