#!/usr/bin/env nu
# Install the ONE local binary you need: the `uncloud` CLI (+ `uc` shortcut).
# Everything else is built in:
#   - servers are installed over SSH by `uc machine init`
#   - getting local Docker images onto the cluster is built into uncloud
#     (`uc build --push` / `uc image push`) — no registry, no extra plugin.

def main [] {
  # Install UPSTREAM uncloud's `uc`. We dropped our fork (2026-06-24): upstream
  # already publishes the same binary assets AND defaults uncloudd to a multi-arch
  # corrosion image (ghcr.io/unlabs-dev/corrosion, has arm64), so no fork is
  # needed. The headless-spinner issue (#386, closed upstream as not-reproducible)
  # is handled by the PTY wrapper in up.nu, not a code patch. Override with
  # UNCLOUD_FORK_REPO / UNCLOUD_FORK_VERSION if you ever need a different build.
  let repo = ($env.UNCLOUD_FORK_REPO? | default "psviderski/uncloud")
  # Pin an explicit upstream release for reproducibility (bump when verified).
  let ver = ($env.UNCLOUD_FORK_VERSION? | default "v0.19.0")
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
