#!/usr/bin/env nu
# Generate state/prices-hetzner-auction.jsonl — the Hetzner server-auction
# (server-börse) "floor" — from the live Robot Webservice
# (robot-ws.your-server.de/order/server_market/product). Same HTTP Basic auth as
# the dedicated feed (HETZNER_ROBOT_USER/PASSWORD).
#
# Auction = USED hardware, sold continuously, so the raw feed is ~100 volatile
# one-off servers. We don't dump those; instead we record the AUCTION FLOOR — the
# cheapest currently-available server per RAM tier — which is small and stable and
# answers "how cheap is dedicated right now". This is much cheaper than new-order
# (state/prices-hetzner-dedicated.jsonl): e.g. 64 GB ~€46/mo auction vs ~€187 new.
#
# Schema (server_market): array of { product: { id, cpu, memory_size (GB int),
# hdd_text, datacenter, price (net monthly string), price_hourly, price_setup } }.
# Dry-run by default; --write persists.

def main [
  --write   # persist to state/prices-hetzner-auction.jsonl (default: dry-run)
] {
  let file = "state/prices-hetzner-auction.jsonl"

  let user = ($env.HETZNER_ROBOT_USER? | default "")
  let pass = ($env.HETZNER_ROBOT_PASSWORD? | default "")
  if ($user | is-empty) or ($pass | is-empty) {
    print -e "✗ Robot web-service credentials not set (HETZNER_ROBOT_USER / HETZNER_ROBOT_PASSWORD)."
    print -e "  Create a web-service user: robot.hetzner.com -> Settings -> 'Web service and app settings'."
    print -e "  Then: fnox set --global -p keychain HETZNER_ROBOT_USER ; fnox set --global -p keychain HETZNER_ROBOT_PASSWORD"
    exit 1
  }

  let resp = (^curl -s -u $"($user):($pass)" "https://robot-ws.your-server.de/order/server_market/product")
  let products = (try { $resp | from json | get product } catch {
    print -e "✗ Robot auction API did not return JSON (auth failure or outage). First 400 chars:"
    print -e ($resp | str substring 0..400)
    exit 1
  })

  # Auction FLOOR: cheapest available server per RAM tier.
  let rows = ($products
    | group-by memory_size
    | items {|mem servers|
        let c = ($servers | sort-by {|s| $s.price | into float } | first)
        {
          category: "compute",
          class: "auction",
          provider: "hetzner-auction",
          sku: $"auction-($mem)gb",
          cpu: $c.cpu,
          ram_gb: ($mem | into int),
          disk: ($c.hdd_text? | default ""),
          eur_per_hour: ($c.price_hourly | into float | math round --precision 4),
          eur_per_month: ($c.price | into float | math round --precision 2),
          setup_fee_eur: ($c.price_setup? | default "0" | into float | math round --precision 2),
          datacenter: $c.datacenter,
          n_available: ($servers | length),
          kvm: true,
        }
      }
    | sort-by ram_gb)

  print $"Hetzner auction floor — cheapest available per RAM tier, ($rows | length) tiers"
  $rows | select sku ram_gb cpu eur_per_month n_available datacenter | table | print

  print ""
  if $write {
    (($rows | each {|r| $r | to json -r} | str join "\n") + "\n") | save -f $file
    print $"✓ wrote ($file) — ($rows | length) auction-floor rows from the live Robot market API."
  } else {
    print $"Dry run — nothing written. Re-run with --write to regenerate ($file)."
  }
}
