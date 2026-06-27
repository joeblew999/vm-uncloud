#!/usr/bin/env nu
# dev:secrets:check — doctor for the OrangeVault dev/CI secrets setup. Verifies the
# vault is reachable and its DOMAIN is correct (Bitwarden clients follow /api/config
# for login/unlock), and which ORANGEVAULT_DEV_* creds are in the keychain. Prints a
# checklist + exact fixes. Never prints secret values.

# Is a keychain item set (non-empty)? Never echoes the value. Returns null if
# fnox isn't installed (so the caller can say "unknown" instead of crashing).
def kc-set [key: string] {
  if (which fnox | is-empty) { return null }
  let r = (do { ^fnox get $key } | complete)
  ($r.exit_code == 0) and (($r.stdout | str trim) != "")
}

def main [] {
  let server = ($env.ORANGEVAULT_DEV_DOMAIN?
    | default "https://orangevault.gedw99.workers.dev"
    | str trim | str trim --char '/' --right)
  print $"OrangeVault dev/CI secrets check — server: ($server)"
  print ""
  mut ok = true

  # 1. reachable + DOMAIN correct
  let cfg = (try { http get $"($server)/api/config" } catch { null })
  if ($cfg == null) {
    print $"  ✗ ($server)/api/config unreachable — is OrangeVault deployed? \(override with ORANGEVAULT_DEV_DOMAIN\)"
    $ok = false
  } else {
    print $"  ✓ reachable \(server.name: ($cfg.server?.name? | default '?')\)"
    let api = ($cfg.environment?.api? | default "")
    if ($api | str starts-with $server) {
      print $"  ✓ DOMAIN correct \(($api)\)"
    } else {
      print $"  ✗ DOMAIN mismatch — /api/config reports '($api)'"
      print "      Bitwarden clients follow that for login/unlock and will FAIL."
      print "      Fix in the orangevault repo:"
      print $"        fnox set --global -p keychain ORANGEVAULT_DOMAIN    # = ($server)"
      print "        mise run cluster:deploy"
      $ok = false
    }
  }
  print ""

  # 2. dedicated dev/CI account creds in the keychain
  print "  dev/CI account creds (keychain):"
  for k in [
    "ORANGEVAULT_DEV_EMAIL"
    "ORANGEVAULT_DEV_BW_CLIENTID"
    "ORANGEVAULT_DEV_BW_CLIENTSECRET"
    "ORANGEVAULT_DEV_MASTER_PASSWORD"
  ] {
    let v = (kc-set $k)
    if ($v == null) { print $"    ? ($k) — fnox not found on PATH"; $ok = false } else if $v { print $"    ✓ ($k)" } else { print $"    ✗ ($k)"; $ok = false }
  }
  print ""

  if $ok {
    print "✓ ready — mise run dev:deploy, then the dev container can `fnox exec` against OrangeVault."
  } else {
    print "✗ not ready. Set missing creds with: mise run dev:secrets:set   (then re-run this check)."
    exit 1
  }
}
