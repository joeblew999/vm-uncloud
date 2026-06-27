#!/usr/bin/env nu
# Config for the dev-windows recipe. recipe.nu runs this with DOMAIN in the env.
# A dev-windows node IS a windows node, so HOST is windows.<domain> (RDP target).
# DEV_SSH_PORT feeds the compose port mapping; SSH_PUBKEY is informational (the
# reliable key path is \\host.lan\Data\dev\authorized_keys — see compose notes).
# No secret is generated: dockur's default account (Docker/admin) is used.

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run dev:win:up' first"
    exit 1
  }

  let port = ($env.DEV_SSH_PORT? | default "2222")

  print -e "dev-windows: heavy + EXPERIMENTAL — deploy onto a cpx42 node set windows=true AND dev=true."
  print -e "dev-windows: first boot installs Windows, then oem/install.bat installs mise + git (+ best-effort OpenSSH)."
  print -e $"dev-windows: RDP at windows.($dom):3389  user 'Docker' / pass 'admin'."
  print -e "dev-windows: get your repo in via \\\\host.lan\\Data (the devwin_shared volume), then run `mise run build` in Windows."
  { HOST: $"windows.($dom)", DEV_SSH_PORT: $port } | to json
}
