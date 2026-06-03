#!/usr/bin/env nu
# Install the two LOCAL binaries Uncloud needs on your machine:
#   1. the `uncloud` CLI (+ `uc` shortcut)
#   2. the `docker-pussh` Docker CLI plugin (direct image push, optional but handy)
# Everything on the servers is installed over SSH by `uc machine init`.

def main [] {
  print "==> Installing the uncloud CLI..."
  if (which uc | is-not-empty) {
    print $"    uc already present at (which uc | get path.0) — skipping."
  } else {
    # Official CLI installer (mac/Linux, amd64/arm64). Installs `uncloud` + `uc` symlink.
    ^curl -fsS https://get.uncloud.run/install.sh | ^sh
  }

  print "==> Installing the docker-pussh CLI plugin..."
  let plugins_dir = ($nu.home-path | path join ".docker" "cli-plugins")
  mkdir $plugins_dir
  let dest = ($plugins_dir | path join "docker-pussh")
  ^curl -sSL https://raw.githubusercontent.com/psviderski/unregistry/main/docker-pussh -o $dest
  ^chmod +x $dest
  print $"    installed -> ($dest)"

  print ""
  print "Done. Next:"
  print "  1. cp tofu/terraform.tfvars.example tofu/terraform.tfvars   # set domain, zone, ssh key"
  print "  2. mise run secrets:set                                     # store API tokens in keychain"
  print "  3. mise run up                                              # build the cluster"
}
