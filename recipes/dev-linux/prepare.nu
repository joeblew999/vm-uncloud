#!/usr/bin/env nu
# Config for the dev-linux recipe. recipe.nu runs this with DOMAIN in the env and
# merges the JSON on stdout into the deploy env; stderr is human notes.
#
# Resolves: (1) the developer's SSH PUBLIC key (authorized in the container so
# Remote-SSH / rsync / `devcontainer exec` can connect), the login user, and the
# host SSH port; (2) the DEDICATED dev/CI OrangeVault account creds (so `fnox
# exec` can pull project secrets in-container — ov-bootstrap unlocks them). No
# secret is generated or persisted here; the OrangeVault creds are READ from the
# operator's fnox keychain (set once with `fnox set --global -p keychain ...`).

# Read a global keychain item via fnox; "" if unset / no keychain (e.g. CI).
def kc [key: string] {
  let r = (do { ^fnox get $key } | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

def main [] {
  let dom = ($env.DOMAIN? | default "")
  if ($dom | is-empty) {
    print -e "no domain — run 'mise run dev:up' first"
    exit 1
  }

  let user = ($env.DEV_USER? | default "vscode")
  let port = ($env.DEV_SSH_PORT? | default "2222")

  # --- SSH public key (authorize the developer in the container) -------------
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

  # --- Dedicated dev/CI OrangeVault account (NEVER your personal vault) -------
  # Set these once on the operator machine, e.g.:
  #   fnox set --global -p keychain ORANGEVAULT_DEV_DOMAIN
  #   fnox set --global -p keychain ORANGEVAULT_DEV_EMAIL
  #   fnox set --global -p keychain ORANGEVAULT_DEV_BW_CLIENTID
  #   fnox set --global -p keychain ORANGEVAULT_DEV_BW_CLIENTSECRET
  #   fnox set --global -p keychain ORANGEVAULT_DEV_MASTER_PASSWORD
  # CI / dry runs don't touch the keychain.
  let dry = (($env.VMU_SECRET_DRY? | default "") == "1")
  let ov_server = (if $dry { "" } else { kc "ORANGEVAULT_DEV_DOMAIN" })
  let ov_email  = (if $dry { "" } else { kc "ORANGEVAULT_DEV_EMAIL" })
  let ov_cid    = (if $dry { "" } else { kc "ORANGEVAULT_DEV_BW_CLIENTID" })
  let ov_csec   = (if $dry { "" } else { kc "ORANGEVAULT_DEV_BW_CLIENTSECRET" })
  let ov_pw     = (if $dry { "" } else { kc "ORANGEVAULT_DEV_MASTER_PASSWORD" })

  if ($ov_server | is-empty) {
    print -e "dev-linux: no dev OrangeVault account configured (ORANGEVAULT_DEV_* not in keychain)."
    print -e "dev-linux: deploying WITHOUT vault secrets — `fnox exec` in-container won't resolve until set + redeploy."
  } else {
    print -e $"dev-linux: vault secrets via OrangeVault \(($ov_server)\) — dev container will `fnox exec` against it."
  }

  print -e $"dev-linux: SSH at dev.($dom):($port)  user '($user)'  -> /workspace \(Remote-SSH / rsync / devcontainer exec\)."
  print -e "dev-linux: toolchains come from each project's mise.toml — sync your repo, then run its `mise run build`."

  {
    HOST: $"dev.($dom)",
    SSH_PUBKEY: $pubkey,
    DEV_USER: $user,
    DEV_SSH_PORT: $port,
    OV_SERVER: $ov_server,
    OV_EMAIL: $ov_email,
    OV_BW_CLIENTID: $ov_cid,
    OV_BW_CLIENTSECRET: $ov_csec,
    OV_MASTER_PASSWORD: $ov_pw
  } | to json
}
