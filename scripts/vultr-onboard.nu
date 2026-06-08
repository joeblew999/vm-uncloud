#!/usr/bin/env nu
# HIL onboarding for the win-kvm / Vultr path. This DOES the work — it runs the
# interactive `fnox set -p keychain` for any missing token (like secrets:set),
# validates the Vultr key against the API, then enumerates the non-secret picks.
# Idempotent: already-set items are skipped. Run interactively:
#   mise run win-kvm:onboard

def has-secret [name: string] {
  (do { ^fnox get $name } | complete).exit_code == 0
}

# Set a keychain secret if missing — invokes fnox's interactive prompt, then
# confirms it landed. Returns true if the secret is set afterwards.
def ensure-secret [name: string] {
  if (has-secret $name) {
    print $"  ✓ ($name) already set"
    return true
  }
  print $"  → setting ($name) — paste the value at the prompt:"
  ^fnox set -p keychain $name
  if (has-secret $name) {
    print $"  ✓ ($name) stored in keychain"
    true
  } else {
    print -e $"  ✗ ($name) still not set"
    false
  }
}

def main [] {
  print "── win-kvm / Vultr onboarding ─────────────────────────────"
  print ""

  # 0. vultr-cli — install via mise if absent ----------------------------------
  if (which vultr-cli | is-empty) {
    print "→ installing vultr-cli (mise)…"
    ^mise install "ubi:vultr/vultr-cli"
  }
  if (which vultr-cli | is-empty) {
    print -e "✗ vultr-cli not on PATH — run `mise install` then retry"; exit 1
  }
  print "✓ vultr-cli installed"
  print ""

  # 1. VULTR_API_KEY — SET it (if missing) then VALIDATE -----------------------
  print "1) Vultr API key  —  https://my.vultr.com/settings/#settingsapi"
  print "   (enable API access + add your public IP to the access-control list)"
  ensure-secret "VULTR_API_KEY" | ignore
  if not (has-secret "VULTR_API_KEY") { print -e "✗ no VULTR_API_KEY — stopping"; exit 1 }
  let valid = ((do { ^fnox exec --if-missing ignore -- vultr-cli account } | complete).exit_code == 0)
  if $valid {
    print "  ✓ key accepted by Vultr"
  } else {
    print -e "  ✗ Vultr rejected the key (wrong value, or your IP isn't allow-listed)."
    print -e "    fix it: `fnox set -p keychain VULTR_API_KEY`, then re-run onboard."
    exit 1
  }
  print ""

  # 2. Vultr SSH key — enumerate; offer to create from your local pubkey -------
  print "2) Vultr SSH key (VULTR_SSH_KEY_ID → mise.local.toml)"
  let keys = (try { (^fnox exec --if-missing ignore -- vultr-cli ssh-key list -o json | from json | get ssh_keys?) | default [] } catch { [] })
  if ($keys | is-empty) {
    let pub = ("~/.ssh/id_ed25519.pub" | path expand)
    if ($pub | path exists) {
      print $"  no Vultr ssh-key yet. Create one from ($pub)?  run:"
      print $"    vultr-cli ssh-key create --name vmu --key (open --raw $pub | str trim)"
    } else {
      print "  no Vultr ssh-key and no ~/.ssh/id_ed25519.pub — add a key, then re-run."
    }
  } else {
    print "  choose an id for VULTR_SSH_KEY_ID:"
    for k in $keys { print $"    ($k.id)  ($k.name)" }
  }
  print ""

  # 3. region + plan — enumerate ----------------------------------------------
  print "3) Region + plan (VULTR_REGION / VULTR_PLAN → mise.local.toml)"
  print "   regions:        vultr-cli regions list"
  print "   bare-metal ≥6c: vultr-cli plans list   (filter to BM)"
  print "   (VULTR_OS_ID defaults to 1743 = Ubuntu 24.04 x64 — fine as-is)"
  print ""

  # 4. R2 creds — OPTIONAL (only needed for snapshot/teardown state) -----------
  print "4) R2 snapshot transit (OPTIONAL — only for preserving the warm cache on teardown)"
  if (has-secret "R2_ACCESS_KEY_ID") and (has-secret "R2_SECRET_ACCESS_KEY") {
    print "  ✓ R2 creds set"
  } else {
    print "  make an R2 API token: Cloudflare dashboard → R2 → Manage API Tokens, then:"
    let ans = (input "  set R2 creds now? [y/N] ")
    if (($ans | str downcase) == "y") {
      ensure-secret "R2_ACCESS_KEY_ID" | ignore
      ensure-secret "R2_SECRET_ACCESS_KEY" | ignore
      print "  (also set R2_ENDPOINT / R2_BUCKET in mise.local.toml — see `mise run r2:bootstrap`)"
    } else {
      print "  skipped — you can boot now and set R2 before your first `win-kvm:snapshot`."
    }
  }
  print ""

  print "───────────────────────────────────────────────────────────"
  print "✓ tokens onboarded. Set the picks above in mise.local.toml, then:"
  print "    mise run win-kvm:up → win-kvm:ip → win-kvm:init → win-kvm:deploy"
}
