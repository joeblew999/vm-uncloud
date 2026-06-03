#!/usr/bin/env nu
# Install the ONE local binary you need: the `uncloud` CLI (+ `uc` shortcut).
# Everything else is built in:
#   - servers are installed over SSH by `uc machine init`
#   - getting local Docker images onto the cluster is built into uncloud
#     (`uc build --push` / `uc image push`) — no registry, no extra plugin.

def main [] {
  print "==> Installing the uncloud CLI..."
  if (which uc | is-not-empty) {
    print $"    uc already present at (which uc | get path.0) — skipping."
  } else {
    # Official CLI installer (mac/Linux, amd64/arm64). Installs `uncloud` + `uc` symlink.
    ^curl -fsS https://get.uncloud.run/install.sh | ^sh
  }

  print ""
  print "Done. Next:"
  print "  1. cp tofu/terraform.tfvars.example tofu/terraform.tfvars   # set domain, zone, ssh key"
  print "  2. mise run secrets:set                                     # store API tokens in keychain"
  print "  3. mise run up                                              # build the cluster"
}
