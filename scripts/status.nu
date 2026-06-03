#!/usr/bin/env nu
# Show infra + cluster state at a glance.

const TOFU = ["-chdir=tofu"]

def main [] {
  print "=== Infrastructure (OpenTofu) ==="
  let out = (^tofu ...$TOFU output -json | complete)
  if $out.exit_code == 0 {
    let o = ($out.stdout | from json)
    print $"  Nodes:   ($o.node_ipv4.value | str join ', ')"
    print $"  Domains: ($o.fqdns.value | str join ', ')"
  } else {
    print "  (no state — run 'mise run up' first)"
  }

  print ""
  print "=== Machines (uncloud) ==="
  ^uc machine ls

  print ""
  print "=== Services (uncloud) ==="
  ^uc ls
}
