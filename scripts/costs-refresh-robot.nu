#!/usr/bin/env nu
# Refresh the hetzner-dedicated (Robot) prices in state/costs.jsonl from the live
# Hetzner ROBOT Webservice (robot-ws.your-server.de/order/server/product). This is
# a SEPARATE API from the Cloud one (scripts/costs-refresh.nu): different host,
# different auth (HTTP Basic with a web-service user, NOT HCLOUD_TOKEN), different
# product line (the new standardized -1/-2/-3 catalog). hcloud can't see dedicated
# pricing at all, hence this companion script.
#
# Touches ONLY rows where category=="compute" AND provider=="hetzner-dedicated",
# and on those ONLY eur_per_month (net monthly) + setup_fee_eur (net setup), and
# only when the row's `sku` matches a live product `id` (case-insensitive). Every
# other field/row is kept byte-for-byte. Legacy SKUs with no live match (e.g.
# ax41-nvme, whose free-config name is going away) are warned + left unchanged —
# existing rented boxes are grandfathered. Dry-run by default; --write persists.
#
# Schema (from the Robot Webservice docs): JSON array of { product: { id, name,
# description, prices: [ { location, price: { net }, price_setup: { net } } ] } }.
#
# Conventions follow scripts/costs-refresh.nu + scripts/status.nu.

def is-hcloud-dedicated [row: record]: nothing -> bool {
  (($row.category? | default "") == "compute") and (($row.provider? | default "") == "hetzner-dedicated")
}

# Round a Robot net price string ("39.0000") to 2dp; null if absent.
def net2 [s: any]: nothing -> any {
  if ($s | is-empty) { null } else { $s | into float | math round --precision 2 }
}

def main [
  --location: string = ""   # filter to a Robot location code (e.g. FSN1); "" = first price per product
  --write                    # persist changes (default: dry-run — writes nothing)
] {
  let file = "state/costs.jsonl"

  let user = ($env.HETZNER_ROBOT_USER? | default "")
  let pass = ($env.HETZNER_ROBOT_PASSWORD? | default "")
  if ($user | is-empty) or ($pass | is-empty) {
    print -e "✗ Robot web-service credentials not set (HETZNER_ROBOT_USER / HETZNER_ROBOT_PASSWORD)."
    print -e "  Create a web-service user: robot.hetzner.com → Settings → 'Web service and app settings'."
    print -e "  Then store them:"
    print -e "    fnox set --global -p keychain HETZNER_ROBOT_USER"
    print -e "    fnox set --global -p keychain HETZNER_ROBOT_PASSWORD"
    exit 1
  }

  # --- live dedicated catalog: id -> {monthly, setup, loc} --------------------
  let raw_resp = (^curl -s -u $"($user):($pass)" "https://robot-ws.your-server.de/order/server/product")
  let products = (try { $raw_resp | from json } catch {
    print -e "✗ Robot API did not return JSON (auth failure or outage). Raw response:"
    print -e ($raw_resp | str substring 0..400)
    exit 1
  })
  let priced = ($products | each {|entry|
    let p = $entry.product
    let rows = (if ($location | is-empty) { $p.prices } else { $p.prices | where {|x| ($x.location | str downcase) == ($location | str downcase) } })
    if ($rows | is-empty) { null } else {
      let pr = ($rows | first)
      { id: $p.id, name: $p.name, loc: $pr.location, monthly: (net2 $pr.price.net?), setup: (net2 $pr.price_setup.net?) }
    }
  } | compact)

  # --- file: raw lines (non-target + blank lines pass through verbatim) -------
  let raw = (open --raw $file | lines)

  # Match a file SKU to a live product id, case-insensitively.
  let find = {|sku| $priced | where {|p| ($p.id | str downcase) == ($sku | str downcase) }}

  let out = ($raw | each {|line|
    if ($line | str trim | is-empty) { $line } else {
      let row = ($line | from json)
      if (not (is-hcloud-dedicated $row)) { $line } else {
        let m = (do $find $row.sku)
        if ($m | is-empty) { $line } else {
          let lp = ($m | first)
          # update ONLY fields that already exist on the row
          mut r = $row
          if ("eur_per_month" in ($row | columns)) and ($lp.monthly != null) { $r = ($r | update eur_per_month $lp.monthly) }
          if ("setup_fee_eur" in ($row | columns)) and ($lp.setup != null) { $r = ($r | update setup_fee_eur $lp.setup) }
          ($r | to json -r)
        }
      }
    }
  })

  # --- diff + unmatched (functional) ------------------------------------------
  let diffs = ($raw | each {|line|
    if ($line | str trim | is-empty) { null } else {
      let row = ($line | from json)
      if (not (is-hcloud-dedicated $row)) { null } else {
        let m = (do $find $row.sku)
        if ($m | is-empty) { null } else {
          let lp = ($m | first)
          { sku: $row.sku, matched_id: $lp.id, "eur_per_month": $"($row.eur_per_month?) -> ($lp.monthly)", "setup_fee_eur": $"($row.setup_fee_eur?) -> ($lp.setup)" }
        }
      }
    }
  } | compact)

  let unmatched = ($raw | each {|line|
    if ($line | str trim | is-empty) { null } else {
      let row = ($line | from json)
      if (is-hcloud-dedicated $row) and ((do $find $row.sku) | is-empty) { $row.sku } else { null }
    }
  } | compact)

  let loc_label = (if ($location | is-empty) { "first price/product" } else { $location })
  print $"Hetzner Robot dedicated price refresh — ($loc_label), file state/costs.jsonl"
  if ($diffs | is-empty) { print "  (no hetzner-dedicated rows matched a live product)" } else { $diffs | table | print }
  for s in $unmatched {
    print -e $"⚠ ($s): no live Robot product with id '($s)' — left unchanged."
    print -e "    Legacy free-config names (e.g. ax41-nvme) are gone for NEW orders under the -1/-2/-3 scheme;"
    print -e "    existing rented boxes are grandfathered. Relabel the row to a current product id to track it."
  }

  # --- live products NOT in the file (the catalog to add/relabel toward) ------
  let file_skus = ($raw | each {|l|
    if ($l | str trim | is-empty) { null } else { let r = ($l | from json); if (is-hcloud-dedicated $r) { $r.sku | str downcase } else { null } }
  } | compact)
  let notinfile = ($priced | where {|p| ($p.id | str downcase) not-in $file_skus } | select id name monthly setup loc)
  if ($notinfile | is-not-empty) {
    print ""
    print "Live Robot products NOT in the file (add rows / relabel toward these):"
    $notinfile | table | print
  }

  # --- write or dry-run -------------------------------------------------------
  print ""
  if $write {
    (($out | str join "\n") + "\n") | save -f $file
    print $"✓ wrote ($file): updated eur_per_month + setup_fee_eur on ($diffs | length) hetzner-dedicated row\(s\). Nothing else touched."
  } else {
    print "Dry run — nothing written. Re-run with --write to persist."
  }
}
