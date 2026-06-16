#!/usr/bin/env nu
# Refresh the hetzner-cloud COMPUTE prices in state/costs.jsonl from the live
# Hetzner Cloud API (`hcloud server-type list`). Hetzner raised Cloud prices in
# 2026 (~30-37% on Apr 1, plus later rounds) but the file was never updated. The
# -1/-2/-3 "standardization" is a dedicated/Robot-only change, so Cloud
# server-type NAMES (cpx22/cpx42/cax11) are unaffected and tofu/ needs nothing —
# only the cost model is wrong.
#
# Touches ONLY rows where category=="compute" AND provider=="hetzner-cloud", and
# on those ONLY eur_per_hour (net hourly, 4dp) + eur_per_month_24x7 (net monthly,
# 2dp) at --location. Every other field on those rows and EVERY other row is kept
# byte-for-byte (non-target lines pass through as their original raw string).
# Robot/dedicated, vultr, equinix, local, storage, egress, software prices aren't
# in the Cloud API, so they're never touched.
#
# Dry-run by default; --write persists. Conventions follow scripts/arm.nu +
# scripts/status.nu (def main, `^hcloud ... -o json | from json`, jsonl via
# `open ... | lines | each { from json }`).

# True for the rows we own: hetzner-cloud compute. (Closures can't mutate outer
# `mut` state, so the whole script is built functionally around this predicate.)
def is-hcloud-compute [row: record]: nothing -> bool {
  (($row.category? | default "") == "compute") and (($row.provider? | default "") == "hetzner-cloud")
}

def main [
  --location: string = "fsn1"   # Hetzner location whose NET price to apply
  --write                        # persist changes (default: dry-run — writes nothing)
] {
  let file = "state/costs.jsonl"

  # --- live prices: name -> {hourly, monthly} net at $location ----------------
  # Types with no price at $location (e.g. some only in ash/hil) drop out.
  let priced = (^hcloud server-type list -o json | from json
    | each {|t|
        let p = ($t.prices | where location == $location)
        if ($p | is-empty) { null } else {
          let pr = ($p | first)
          {
            name: $t.name,
            hourly: ($pr.price_hourly.net | into float | math round --precision 4),
            monthly: ($pr.price_monthly.net | into float | math round --precision 2),
          }
        }
      }
    | compact)

  # --- file: raw lines (non-target lines pass through verbatim) ---------------
  # Keep blank lines too: `open --raw | lines` strips exactly one trailing
  # newline, so `(... | str join "\n") + "\n"` below round-trips EOF byte-exact
  # (incl. the file's trailing blank line).
  let raw = (open --raw $file | lines)

  # Rewrite ONLY target rows; keep every other line (incl. blanks) verbatim.
  let out = ($raw | each {|line|
    if ($line | str trim | is-empty) { $line } else {
      let row = ($line | from json)
      if (is-hcloud-compute $row) {
        let m = ($priced | where name == $row.sku)
        if ($m | is-empty) {
          $line
        } else {
          let lp = ($m | first)
          ($row
            | upsert eur_per_hour $lp.hourly
            | upsert eur_per_month_24x7 $lp.monthly
            | to json -r)
        }
      } else {
        $line
      }
    }
  })

  # --- old -> new diff table (functional) -------------------------------------
  let diffs = ($raw | each {|line|
    if ($line | str trim | is-empty) { null } else {
      let row = ($line | from json)
      if (not (is-hcloud-compute $row)) { null } else {
        let m = ($priced | where name == $row.sku)
        if ($m | is-empty) { null } else {
          let lp = ($m | first)
          {
            sku: $row.sku,
            "eur_per_hour": $"($row.eur_per_hour?) -> ($lp.hourly)",
            "eur_per_month_24x7": $"($row.eur_per_month_24x7?) -> ($lp.monthly)",
          }
        }
      }
    }
  } | compact)

  # SKUs in the file but absent from live output at $location → warn, unchanged.
  let missing = ($raw | each {|line|
    if ($line | str trim | is-empty) { null } else {
      let row = ($line | from json)
      if (is-hcloud-compute $row) and ($priced | where name == $row.sku | is-empty) { $row.sku } else { null }
    }
  } | compact)

  print $"Hetzner Cloud price refresh — location ($location), file state/costs.jsonl"
  if ($diffs | is-empty) {
    print "  (no hetzner-cloud compute rows matched)"
  } else {
    $diffs | table | print
  }
  for s in $missing { print -e $"⚠ ($s): not in live ($location) output — left unchanged \(deprecated?\)" }

  # --- live cpx*/cax*/ccx* types NOT in the file (so you can add rows) --------
  let file_skus = ($raw | each {|l|
    if ($l | str trim | is-empty) { null } else {
      let r = ($l | from json)
      if (is-hcloud-compute $r) { $r.sku } else { null }
    }
  } | compact)
  let notinfile = ($priced
    | where {|p| (($p.name | str starts-with "cpx") or ($p.name | str starts-with "cax") or ($p.name | str starts-with "ccx")) and ($p.name not-in $file_skus) }
    | select name hourly monthly)
  if ($notinfile | is-not-empty) {
    print ""
    print "Live cpx*/cax*/ccx* types NOT in the file (add rows if wanted):"
    print "  note: cpx22 (default node) + cax11 (ARM node) are referenced in tofu/ + README but missing here."
    $notinfile | rename sku eur_per_hour eur_per_month_24x7 | table | print
  }

  # --- flag (do NOT auto-edit) the one row the tier change touches ------------
  # The -1/-2/-3 (+ -Ltd) "standardization" is dedicated/Robot-only, so it leaves
  # Cloud cpx*/cax* names alone but DOES affect Robot SKUs like ax41-nvme — whose
  # prices aren't in the Cloud API, so this script can't refresh them.
  let has_ax41 = ($raw | any {|l|
    if ($l | str trim | is-empty) { false } else {
      let r = ($l | from json)
      (($r.provider? | default "") == "hetzner-dedicated") and (($r.sku? | default "") == "ax41-nvme")
    }
  })
  if $has_ax41 {
    print ""
    print "TODO (manual — NOT auto-edited): hetzner-dedicated 'ax41-nvme'"
    print "  • Robot prices aren't in the Cloud API, so this script never touches it."
    print "  • The free-config name 'ax41-nvme' is going away for NEW orders under the"
    print "    -1/-2/-3 (+ -Ltd) scheme. Relabel/reprice this row by hand from robot.hetzner.com."
    print "  • Existing rented boxes are grandfathered at the old config + price."
  }

  # --- write or dry-run -------------------------------------------------------
  print ""
  if $write {
    (($out | str join "\n") + "\n") | save -f $file
    print $"✓ wrote ($file): updated eur_per_hour + eur_per_month_24x7 on ($diffs | length) hetzner-cloud compute row\(s\). Nothing else touched."
  } else {
    print "Dry run — nothing written. Re-run with --write to persist."
  }
}
