#!/usr/bin/env nu
# Show infra + cluster state at a glance.

use r2.nu *

const TOFU = ["-chdir=tofu"]

def main [] {
  load-env (r2-creds)   # R2 state creds (no-op for local state)
  print "=== Infrastructure (OpenTofu) ==="
  let out = (^tofu ...$TOFU output -json | complete)
  if $out.exit_code == 0 {
    let o = ($out.stdout | from json)
    print $"  Nodes:    ($o.node_ipv4.value | str join ', ')"
    print $"  Wildcard: ($o.wildcard.value)"
  } else {
    print "  (no state — run 'mise run up' first)"
  }

  print ""
  print "=== Machines (uncloud) ==="
  ^uncloud machine ls

  print ""
  print "=== Services (uncloud) ==="
  ^uncloud ls

  print ""
  print "=== History (state/log.jsonl, last 10) ==="
  if ("state/log.jsonl" | path exists) {
    open state/log.jsonl | lines | last 10 | each {|l| $l | from json} | table
  } else {
    print "  (no events yet)"
  }
}
