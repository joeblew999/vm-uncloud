#!/usr/bin/env nu
# Install the ONE local binary you need: the `uncloud` CLI (+ `uc` shortcut).
# Everything else is built in:
#   - servers are installed over SSH by `uc machine init`
#   - getting local Docker images onto the cluster is built into uncloud
#     (`uc build --push` / `uc image push`) — no registry, no extra plugin.

def main [] {
  # Install OUR uncloud fork's `uc`. It embeds our install.sh (defaults uncloudd
  # to joeblew999/uncloud) and our corrosion-image default — so the whole stack
  # runs off our forks with no further config. Override repo with UNCLOUD_FORK_REPO.
  let repo = ($env.UNCLOUD_FORK_REPO? | default "joeblew999/uncloud")
  # PINNED — fork tags use a `-jb.N` PRERELEASE suffix, which semver-sorts BELOW
  # the base version, so "latest" resolution is unreliable (a stray plain tag
  # would outrank it). Always pin an explicit tag for reproducibility. Bump this
  # when a newer fork release is verified. Override with UNCLOUD_FORK_VERSION.
  let ver = ($env.UNCLOUD_FORK_VERSION? | default "v0.20.0-jb.3")
  print $"==> Installing the uncloud CLI from ($repo) @ ($ver)..."
  if (which uc | is-not-empty) {
    print $"    uc already present at (which uc | get path.0) — skipping."
  } else {
    let os = (if $nu.os-info.name == "macos" { "macos" } else { "linux" })
    let arch = (if ($nu.os-info.arch | str contains "aarch64") or ($nu.os-info.arch | str contains "arm64") { "arm64" } else { "amd64" })
    let asset = $"uncloud_($os)_($arch).tar.gz"
    let tmp = (mktemp -d)
    ^gh release download $ver --repo $repo --pattern $asset --dir $tmp
    ^tar -xzf $"($tmp)/($asset)" -C $tmp
    let bindir = $"($nu.home-dir)/.local/bin"
    mkdir $bindir
    ^install -m 0755 $"($tmp)/uncloud" $"($bindir)/uncloud"
    ^ln -sf $"($bindir)/uncloud" $"($bindir)/uc"
    ^rm -rf $tmp
    print $"    installed uncloud + uc → ($bindir) \(ensure it's on PATH)"
  }

  print ""
  print "Done. Next:"
  print "  1. cp tofu/terraform.tfvars.example tofu/terraform.tfvars   # set domain, zone, ssh key"
  print "  2. mise run secrets:set                                     # store API tokens in keychain"
  print "  3. mise run up                                              # build the cluster"
}
