#!/usr/bin/env nu
# Config for the Windows recipe. recipe.nu runs this with DOMAIN in the env and
# merges the JSON on stdout into the deploy env. Notes go to stderr.
#
# No generated secret here on purpose: dockur's default account (Docker/admin)
# is used, so there is no password env to inject (which also dodges the uncloud
# env-newline quirk). Change the password inside Windows on first login.

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run up' first"
    exit 1
  }
  print -e "windows: heavy workload — deploy onto a cpx42-class node, NOT the cpx22 cluster node."
  print -e "windows: first boot downloads the Windows ISO + runs unattended setup (~15-30 min on TCG)."
  print -e $"windows: RDP at <node-ip>:3389  user 'Docker' / pass 'admin'  \(needs a :3389 firewall rule\)."
  print -e "windows: web viewer (8006, no auth) via SSH tunnel: ssh -L 8006:localhost:8006 root@<node-ip>"
  # HOST is cosmetic here (no public route by default); report the node-level handle.
  { HOST: $"windows.($dom)" } | to json
}
