#!/usr/bin/env nu
# Config for the windows-kvm recipe (KVM-accelerated Windows on a bare-metal
# node). Same as the `windows` recipe's prepare.nu — dockur defaults (Docker/
# admin), no injected secret. Deploy onto a /dev/kvm node in the win-kvm context.

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — provision the win-kvm node first (win-kvm:up)"
    exit 1
  }
  print -e "windows-kvm: requires /dev/kvm on the node (Vultr BM / Hetzner Robot / KVM host)."
  print -e "windows-kvm: native-speed (unlike TCG `windows`). First boot installs Windows (~15-30 min)."
  print -e $"windows-kvm: RDP at <node-ip>:3389  user 'Docker' / pass 'admin'."
  print -e "windows-kvm: noVNC (8006) via SSH tunnel: ssh -L 8006:localhost:8006 root@<node-ip>"
  { HOST: $"windows.($dom)" } | to json
}
