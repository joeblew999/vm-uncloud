#!/usr/bin/env nu
# Provision a Vultr Bare Metal node (KVM-capable) and make it an uncloud
# machine in the win-kvm context — the bare-metal path for KVM-fast Windows
# (Hetzner Cloud has no /dev/kvm). Bootstraps with the SAME cloud-init as the
# Hetzner nodes (cloud-init/uncloud.yaml), so the BM becomes a normal uncloud
# node; KVM comes from the windows-kvm recipe's /dev/kvm device.
#
# NEEDS (in mise.local.toml / fnox):
#   VULTR_API_KEY (keychain), VULTR_REGION, VULTR_PLAN (>=6c BM), VULTR_OS_ID
#   (Ubuntu 24.04), VULTR_SSH_KEY_ID. List options: `vultr-cli regions/plans/os list`.
#
# Vultr BM is async (IP assigned after a few min). This creates it and prints
# the next steps; `win-kvm:init` runs `uc machine init` once the IP is up.

def need [k: string] {
  if (($env | get -o $k | default "") | is-empty) {
    print -e $"($k) not set — see mise.local.toml.example / `mise run prices:show` for sizing"
    exit 1
  }
}

def main [] {
  for k in ["VULTR_REGION" "VULTR_PLAN" "VULTR_OS_ID" "VULTR_SSH_KEY_ID"] { need $k }
  let label = ($env.VULTR_LABEL? | default "win-kvm")

  print $"creating Vultr Bare Metal: label=($label) region=($env.VULTR_REGION) plan=($env.VULTR_PLAN)"
  ^fnox exec --if-missing ignore -- vultr-cli bare-metal create --region $env.VULTR_REGION --plan $env.VULTR_PLAN --os $env.VULTR_OS_ID --ssh $env.VULTR_SSH_KEY_ID --label $label --hostname $label --userdata-file cloud-init/uncloud.yaml

  do { nu state/log.nu up --cluster win-kvm --server-type $env.VULTR_PLAN } | ignore

  print ""
  print "Vultr BM provisioning started (async, ~5-10 min to boot). Next:"
  print "  mise run win-kvm:ip       # poll until an IP is assigned"
  print "  mise run win-kvm:init     # uc machine init root@<ip> --context win-kvm"
  print "  mise run win-kvm:deploy   # recipe windows-kvm onto it"
}
