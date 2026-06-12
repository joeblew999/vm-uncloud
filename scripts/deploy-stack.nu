#!/usr/bin/env nu
# One command to deploy the whole Rauthy + Cedar stack across its repos +
# Hetzner + Cloudflare. The map lives in deploy-stack.nuon; this is the generic
# runner.
#
#   mise run deploy:stack            # DRY — prints the ordered plan, no spend
#   mise run deploy:stack -- --execute
#
# DRY is the default on purpose: --execute spends real money (a Hetzner node)
# and pushes to Cloudflare. Read the dry plan first.
use secrets.nu *

def banner [n: string] { print $"\n══ ($n) ══" }

def main [--execute] {
  let cfg = (open deploy-stack.nuon)
  let dom = $cfg.domain
  let mode = (if $execute { "EXECUTE" } else { "DRY" })
  print $"deploy-stack  domain=($dom)  mode=($mode)"

  # ── Phase 0: the contract ────────────────────────────────────────────────
  banner "0 · contract"
  print $"  shared secret: ($cfg.shared_secret_item)  \(fnox keychain — used by the"
  print $"                 bridge webhook ?key= AND saasmail RAUTHY_WEBHOOK_SECRET\)"
  if $execute {
    let s = (secret $cfg.shared_secret_item 64)
    print $"  ✓ ensured \(len ($s | str length)\)"
  }

  # ── Phase 1: server plane (Hetzner) ──────────────────────────────────────
  banner "1 · server plane → Hetzner"
  print $"  mise run up                      # provision cluster \(€ — real node\)"
  print $"  mise run recipe ($cfg.server.recipe)            # Rauthy + email bridge → id.($dom)"
  if $execute {
    nu scripts/up.nu
    nu scripts/recipe.nu $cfg.server.recipe
  }

  # ── Phase 2: verify the seam (issuer must be https) ──────────────────────
  banner "2 · verify issuer"
  let disco = $"https://id.($dom)/auth/v1/.well-known/openid-configuration"
  print $"  GET ($disco) → assert issuer starts with https://"
  if $execute {
    let iss = (do { ^curl -fsS $disco } | complete | get stdout | from json | get issuer)
    if ($iss | str starts-with "https://") {
      print $"  ✓ issuer = ($iss)"
    } else {
      print -e $"  ✗ issuer is NOT https: ($iss) — fix Caddy X-Forwarded-Proto before edge deploy"
      exit 1
    }
  }

  # ── Phase 3: edge plane (Cloudflare) ─────────────────────────────────────
  banner "3 · edge plane → Cloudflare"
  for e in $cfg.edge {
    print $"  • ($e.name)  \(($e.path)\)"
    print $"      vars:    ($e.vars? | default {} | columns | str join ', ')"
    print $"      secrets: ($e.wrangler_secrets? | default [] | str join ', ')"
    print $"      deploy:  ($e.deploy)"
    if $execute {
      let dir = $e.path
      if not ($dir | path exists) { print -e $"  ✗ missing repo: ($dir)"; continue }
      # Push wrangler secrets from the shared fnox item.
      for sname in ($e.wrangler_secrets? | default []) {
        let val = (secret $cfg.shared_secret_item 64)
        $val | with-env { CLOUDFLARE_DEPLOY: "1" } { cd $dir; $val | ^wrangler secret put $sname }
      }
      # Run the repo's own deploy with the shared vars in env.
      with-env ($e.vars? | default {}) { cd $dir; ^nu -c $e.deploy }
    }
  }

  # ── Phase 4: the one manual gate ─────────────────────────────────────────
  banner "4 · manual (one-time, can't be scripted)"
  print $"  Onboard the sending domain at Cloudflare Email Service \(DNS records\):"
  print $"    https://dash.cloudflare.com/?to=/:account/email-service"
  print $"  Until done, CF won't send Rauthy's mail. Verify by triggering a"
  print $"  password reset and watching `uc logs bridge`."

  if (not $execute) {
    print "\n(DRY — nothing deployed. Re-run with --execute to spend + ship.)"
  }
}
