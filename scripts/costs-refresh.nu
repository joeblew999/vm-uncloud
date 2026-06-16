#!/usr/bin/env nu
# Generate state/prices-hetzner-cloud.jsonl — the Hetzner Cloud VPS price catalog — from the
# live hcloud API (`hcloud server-type list`). This file is OWNED by this script:
# it's a straight live dump (all non-deprecated cpx*/cax*/ccx* at --location), so
# there's nothing to hand-maintain and no rows can go stale or missing.
#
# Dedicated (Hetzner Robot) lives in state/prices-hetzner-dedicated.jsonl (costs:refresh-robot);
# everything static (storage/egress/software + non-Hetzner compute) in
# state/prices-static.jsonl. See docs/PLACEMENT.md for which node class runs what.
#
# Dry-run by default (prints the catalog); --write persists. Net prices, monthly
# 2dp / hourly 4dp. Conventions: `^hcloud ... -o json | from json`, jsonl one
# object per line + trailing newline.

def main [
  --location: string = "fsn1"   # Hetzner location whose NET price to record
  --write                        # persist to state/prices-hetzner-cloud.jsonl (default: dry-run)
] {
  let file = "state/prices-hetzner-cloud.jsonl"

  let rows = (^hcloud server-type list -o json | from json
    | where {|t| (not $t.deprecated) and (($t.name | str starts-with "cpx") or ($t.name | str starts-with "cax") or ($t.name | str starts-with "ccx")) }
    | each {|t|
        let p = ($t.prices | where location == $location)
        if ($p | is-empty) { null } else {
          let pr = ($p | first)
          {
            category: "compute",
            class: "vps",
            provider: "hetzner-cloud",
            sku: $t.name,
            cpu: $t.cores,
            cpu_type: $t.cpu_type,
            arch: $t.architecture,
            ram_gb: $t.memory,
            disk_gb: $t.disk,
            eur_per_hour: ($pr.price_hourly.net | into float | math round --precision 4),
            eur_per_month_24x7: ($pr.price_monthly.net | into float | math round --precision 2),
            kvm: false,
            location: $location,
          }
        }
      }
    | compact
    | sort-by sku)

  print $"Hetzner Cloud VPS catalog — location ($location), ($rows | length) types"
  $rows | select sku cpu ram_gb disk_gb arch eur_per_hour eur_per_month_24x7 | table | print

  print ""
  if $write {
    (($rows | each {|r| $r | to json -r} | str join "\n") + "\n") | save -f $file
    print $"✓ wrote ($file) — ($rows | length) Hetzner Cloud VPS rows from the live API."
  } else {
    print $"Dry run — nothing written. Re-run with --write to regenerate ($file)."
  }
}
