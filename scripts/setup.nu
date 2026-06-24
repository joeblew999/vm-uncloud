#!/usr/bin/env nu
# One-time setup notes. The `uncloud` CLI is a normal mise tool now
# (mise.toml [tools] → github:psviderski/uncloud), so `mise install` provides it
# — no out-of-band binary, no custom download. This task just ensures the tools
# are installed and prints the next steps.

def main [] {
  print "==> Ensuring tools are installed (mise)…"
  ^mise install
  let uncloud = (which uncloud | get path?.0? | default "")
  if ($uncloud | is-empty) {
    print -e "✗ `uncloud` not on PATH after `mise install` — run `mise install` then re-run, or check mise activation."
    exit 1
  }
  print $"✓ uncloud CLI: ($uncloud)"

  print ""
  print "Done. Next:"
  print "  1. cp tofu/terraform.tfvars.example tofu/terraform.tfvars   # set domain, zone, ssh key"
  print "  2. mise run secrets:set                                     # store API tokens in keychain"
  print "  3. mise run up                                              # build the cluster"
}
