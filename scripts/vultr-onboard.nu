#!/usr/bin/env nu
# HIL onboarding for the win-kvm / Vultr Bare Metal path.
#
# Checks every prerequisite and, for anything missing, prints exactly what to get
# (with the URL) and the command to set it. Idempotent — re-run until all ✓, then
# `mise run win-kvm:up`. Invoked via `mise run win-kvm:onboard`.

def has-secret [name: string] {
  (do { ^fnox get $name } | complete).exit_code == 0
}

def main [] {
  mut todo = []
  print "── win-kvm / Vultr onboarding ─────────────────────────────"
  print ""

  # 1. vultr-cli (provided by mise [tools]) ------------------------------------
  let have_cli = (which vultr-cli | is-not-empty)
  if $have_cli {
    print "✓ vultr-cli installed"
  } else {
    print "✗ vultr-cli not found"
    print "    → run: mise install   (it's pinned in [tools])"
    $todo = ($todo | append "mise install (vultr-cli)")
  }

  # 2. VULTR_API_KEY (keychain) + validity -------------------------------------
  mut key_ok = false
  if not (has-secret "VULTR_API_KEY") {
    print "✗ VULTR_API_KEY not in keychain"
    print "    → get one: https://my.vultr.com/settings/#settingsapi"
    print "      (enable API access + add your public IP to the access-control list)"
    print "    → set it:  fnox set -p keychain VULTR_API_KEY"
    $todo = ($todo | append "set VULTR_API_KEY")
  } else if $have_cli {
    let r = (do { ^fnox exec --if-missing ignore -- vultr-cli account } | complete)
    if $r.exit_code == 0 {
      print "✓ VULTR_API_KEY set and accepted by Vultr"
      $key_ok = true
    } else {
      print "✗ VULTR_API_KEY set but Vultr rejected it (bad key, or IP not allow-listed)"
      $todo = ($todo | append "fix VULTR_API_KEY")
    }
  } else {
    print "• VULTR_API_KEY set (validate after `mise install`)"
  }

  # 3. With a working key: enumerate the non-secret picks ----------------------
  if $key_ok {
    print ""
    print "Pick these in mise.local.toml (not secret):"
    let keys = (try {
      (^fnox exec --if-missing ignore -- vultr-cli ssh-key list -o json | from json | get ssh_keys?) | default []
    } catch { [] })
    if ($keys | is-empty) {
      print "  ✗ VULTR_SSH_KEY_ID — no SSH key in your Vultr account. Add one:"
      print '      vultr-cli ssh-key create --name vmu --key "$(cat ~/.ssh/id_ed25519.pub)"'
      $todo = ($todo | append "add + set VULTR_SSH_KEY_ID")
    } else {
      print "  → VULTR_SSH_KEY_ID — choose one:"
      for k in $keys { print $"      ($k.id)  ($k.name)" }
    }
    print "  → VULTR_REGION — list: vultr-cli regions list"
    print "  → VULTR_PLAN   — bare-metal, >=6 cores: vultr-cli plans list (filter BM)"
    print "  • VULTR_OS_ID  — default 1743 (Ubuntu 24.04 x64) is fine"
  }

  # 4. R2 snapshot transit (keeps the warm build cache across teardown) --------
  print ""
  print "R2 snapshot transit (so teardown preserves the warm cache):"
  for s in ["R2_ACCESS_KEY_ID" "R2_SECRET_ACCESS_KEY"] {
    if (has-secret $s) {
      print $"  ✓ ($s) set"
    } else {
      print $"  ✗ ($s) — run `mise run r2:bootstrap`, then: fnox set -p keychain ($s)"
      $todo = ($todo | append $"set ($s)")
    }
  }
  if ((($env.R2_ENDPOINT? | default "") | is-empty) or (($env.R2_BUCKET? | default "") | is-empty)) {
    print "  ✗ R2_ENDPOINT / R2_BUCKET — set in mise.local.toml (see `mise run r2:bootstrap`)"
    $todo = ($todo | append "set R2_ENDPOINT / R2_BUCKET")
  } else {
    print "  ✓ R2_ENDPOINT / R2_BUCKET set"
  }

  # Summary --------------------------------------------------------------------
  print ""
  print "───────────────────────────────────────────────────────────"
  if ($todo | is-empty) {
    print "✓ Ready. Next: mise run win-kvm:up → win-kvm:init → win-kvm:deploy"
  } else {
    print $"TODO \(($todo | length)\):"
    for t in $todo { print $"  • ($t)" }
    print ""
    print "Re-run `mise run win-kvm:onboard` after each step."
  }
}
