#!/usr/bin/env nu
# Config for the macos-kvm recipe (KVM-accelerated macOS on a bare-metal node).
# Same shape as windows-kvm's prepare.nu — dockur handles first-boot setup via
# the viewer; no injected secret. Deploy onto a /dev/kvm node.
#
# ⚠️ macOS on non-Apple hardware violates Apple's EULA — see compose.yaml /
# docs/github-ci.md before any shared/public use.

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — provision a KVM node first (win-kvm:up) and deploy into a context"
    exit 1
  }
  print -e "macos-kvm: requires /dev/kvm on the node (Vultr BM / Hetzner Robot / KVM host)."
  print -e "macos-kvm: first boot downloads + installs macOS (~30-60 min); finish setup via the viewer."
  print -e "macos-kvm: noVNC (8006) via SSH tunnel: ssh -L 8006:localhost:8006 root@<node-ip>"
  print -e "macos-kvm: for headless builds, enable Remote Login (SSH) inside the guest after setup."
  print -e "macos-kvm: ⚠️ macOS on non-Apple HW violates Apple's EULA — confirm posture before shared/public CI."
  { HOST: $"macos.($dom)" } | to json
}
