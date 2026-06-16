#!/usr/bin/env nu
# Generate state/prices-hetzner-dedicated.jsonl — the Hetzner dedicated (Robot) price
# catalog — from the live Robot Webservice (robot-ws.your-server.de/order/server/
# product). SEPARATE API from the Cloud one: different host, different auth (HTTP
# Basic with a web-service user, NOT HCLOUD_TOKEN). hcloud can't see dedicated
# pricing at all, hence this companion to prices:refresh:hetzner-cloud.
#
# This file is OWNED by this script — a straight live dump of the standardized
# new-order line (AX*/EX*/SX*/GEX*, ids like AX42-1). Net monthly + setup, specs
# parsed from the product description. NOTE: these are NEW-ORDER prices; the cheap
# legacy "auction" (server-börse) is a different feed (future --auction mode).
#
# Schema: JSON array of { product: { id, name, description[], prices: [ { location,
# price: { net }, price_setup: { net } } ] } }. Dry-run by default; --write persists.

def main [
  --location: string = ""   # filter to a Robot location code (e.g. FSN1); "" = first price/product
  --write                    # persist to state/prices-hetzner-dedicated.jsonl (default: dry-run)
] {
  let file = "state/prices-hetzner-dedicated.jsonl"

  let user = ($env.HETZNER_ROBOT_USER? | default "")
  let pass = ($env.HETZNER_ROBOT_PASSWORD? | default "")
  if ($user | is-empty) or ($pass | is-empty) {
    print -e "✗ Robot web-service credentials not set (HETZNER_ROBOT_USER / HETZNER_ROBOT_PASSWORD)."
    print -e "  Create a web-service user: robot.hetzner.com -> Settings -> 'Web service and app settings'."
    print -e "  Then: fnox set --global -p keychain HETZNER_ROBOT_USER ; fnox set --global -p keychain HETZNER_ROBOT_PASSWORD"
    exit 1
  }

  let resp = (^curl -s -u $"($user):($pass)" "https://robot-ws.your-server.de/order/server/product")
  let products = (try { $resp | from json } catch {
    print -e "✗ Robot API did not return JSON (auth failure or outage). First 400 chars:"
    print -e ($resp | str substring 0..400)
    exit 1
  })

  let rows = ($products
    # standardized line only: ids like AX42-1 / EX131-2 / GEX44-1 (skip the
    # space/™ auction-gen "Dell PowerEdge…" descriptive names).
    | where {|e| ($e.product.id | str trim) =~ '^[A-Za-z]+[0-9]+-[0-9]+$' }
    | each {|e|
        let p = $e.product
        let prs = (if ($location | is-empty) { $p.prices } else { $p.prices | where {|x| ($x.location | str downcase) == ($location | str downcase) } })
        if ($prs | is-empty) { null } else {
          let pr = ($prs | first)
          let ramline = ($p.description | where {|d| $d | str contains "RAM" } | get 0? | default "")
          let ram = ($ramline | parse --regex '(?<n>[0-9]+)\s*GB' | get n.0? | default "")
          let disk = ($p.description | where {|d| ($d | str contains "SSD") or ($d | str contains "NVMe") or ($d | str contains "HDD") } | get 0? | default "")
          {
            category: "compute",
            class: "dedicated",
            provider: "hetzner-dedicated",
            sku: $p.id,
            cpu: ($p.description | get 0? | default ""),
            ram_gb: (if ($ram | is-empty) { null } else { $ram | into int }),
            disk: $disk,
            eur_per_month: ($pr.price.net | into float | math round --precision 2),
            setup_fee_eur: ($pr.price_setup.net | into float | math round --precision 2),
            kvm: true,
            location: $pr.location,
          }
        }
      }
    | compact
    | sort-by eur_per_month)

  print $"Hetzner dedicated Robot new-order catalog — ($rows | length) products"
  $rows | select sku ram_gb eur_per_month setup_fee_eur location | table | print

  print ""
  if $write {
    (($rows | each {|r| $r | to json -r} | str join "\n") + "\n") | save -f $file
    print $"✓ wrote ($file) — ($rows | length) Hetzner dedicated rows from the live Robot API."
  } else {
    print $"Dry run — nothing written. Re-run with --write to regenerate ($file)."
  }
}
