#!/usr/bin/env nu
# Config for the dev-linux recipe. recipe.nu runs this with DOMAIN in the env and
# merges the JSON on stdout into the deploy env; stderr is human notes.
#
# It resolves the developer's SSH PUBLIC key (authorized inside the container so
# VS Code Remote-SSH / rsync / `devcontainer exec` can connect) plus the login
# user and the host SSH port. No secret is generated — the key already exists on
# the operator's machine; nothing is persisted.

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run dev:up' first"
    exit 1
  }

  let user = ($env.DEV_USER? | default "vscode")
  let port = ($env.DEV_SSH_PORT? | default "2222")

  # SSH_PUBKEY: DEV_SSH_PUBKEY wins (a literal key OR a path); else the first
  # existing default key. Missing is non-fatal (CI / first scaffolding) — we warn
  # and deploy without an authorized key (the container entrypoint warns too).
  let explicit = ($env.DEV_SSH_PUBKEY? | default "")
  mut pubkey = ""
  if ($explicit | is-not-empty) {
    $pubkey = (if ($explicit | path exists) { open --raw $explicit | str trim } else { $explicit | str trim })
  } else {
    let files = ([
        "~/.ssh/id_ed25519.pub"
        "~/.ssh/id_rsa.pub"
        "~/.ssh/gedw99_hetzner.pub"
      ] | each {|p| $p | path expand } | where {|p| $p | path exists })
    if ($files | is-not-empty) { $pubkey = (open --raw ($files | first) | str trim) }
  }

  if ($pubkey | is-empty) {
    print -e "dev-linux: no SSH public key found (set DEV_SSH_PUBKEY or create ~/.ssh/id_ed25519.pub)."
    print -e "dev-linux: deploying WITHOUT an authorized key — nobody can SSH in until you set one + redeploy."
  }

  print -e $"dev-linux: SSH at dev.($dom):($port)  user '($user)'  -> /workspace \(Remote-SSH / rsync / devcontainer exec\)."
  print -e "dev-linux: toolchains come from each project's mise.toml — sync your repo, then run its `mise run build`."
  { HOST: $"dev.($dom)", SSH_PUBKEY: $pubkey, DEV_USER: $user, DEV_SSH_PORT: $port } | to json
}
