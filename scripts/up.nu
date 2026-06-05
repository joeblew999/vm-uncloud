#!/usr/bin/env nu
# Provision Hetzner + (optional) Cloudflare DNS via OpenTofu, then turn each
# server into an Uncloud machine over SSH. Idempotent — re-running reconciles.
#
# Tokens (HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN) are injected by `fnox exec` from
# the keychain; the tofu providers read them straight from the environment.
# SSH key comes from tofu (var ssh_private_key_file, set in terraform.tfvars).

use r2.nu *

const TOFU = ["-chdir=tofu"]

def main [] {
  # If remote (R2) state is active, derive its S3 creds from the CF token so
  # every tofu command below can read/write state. No-op for local state.
  load-env (r2-creds)

  if not ("tofu/terraform.tfvars" | path exists) {
    print "ERROR: tofu/terraform.tfvars not found."
    print "       cp tofu/terraform.tfvars.example tofu/terraform.tfvars and edit it."
    exit 1
  }

  print "==> tofu init"
  ^tofu ...$TOFU init -input=false

  # tofu apply blocks until the box is fully READY: its remote-exec provisioner
  # waits for SSH (native connection retry) then `cloud-init status --wait`.
  # No sleep/poll here — when this returns, the machine is ready for init.
  print "==> tofu apply (server + DNS + waits for cloud-init via provisioner)"
  ^tofu ...$TOFU apply -auto-approve -input=false

  let out = (^tofu ...$TOFU output -json | from json)
  let ips = ($out.node_ipv4.value)
  let domain = ($out.domain.value)
  let wildcard = ($out.wildcard.value)
  print $"==> Servers: ($ips | str join ', ')"
  if ($domain | is-not-empty) { print $"==> Wildcard: ($wildcard) -> ($ips | get 0)" }

  let key = ($out.ssh_private_key_file.value | path expand)
  # Clear stale host keys (Hetzner recycles IPs) so client-side `uc machine init`
  # doesn't trip on a mismatched known_hosts entry. One-shot, not a poll.
  for ip in $ips { ^ssh-keygen -R $ip out+err> /dev/null }

  # Context name MUST match $UNCLOUD_CONTEXT — `uc machine init` does NOT read
  # that env var (it defaults the new context to "default"), so we pass it
  # explicitly. Otherwise deploy/recipe/down would look for a context the init
  # step never created.
  let ctx = ($env.UNCLOUD_CONTEXT? | default "hetzner")

  # When we have a domain we deploy our own wildcard/DNS-01 Caddy below, so skip
  # the default Caddy at init time (--no-caddy). --no-dns: we manage DNS via
  # Cloudflare, not the uncld.dev rental.
  let caddy_flag = (if ($domain | is-empty) { [] } else { [--no-caddy] })

  # First node initialises the cluster; the rest join the WireGuard mesh.
  $ips | enumerate | each {|row|
    let ip = $row.item
    let mname = $"($ctx)-($row.index + 1)"
    if $row.index == 0 {
      print $"==> uc machine init root@($ip) --context ($ctx) --name ($mname) --no-dns"
      ^uc machine init $"root@($ip)" --context $ctx --name $mname --no-dns ...$caddy_flag -i $key -y
    } else {
      print $"==> uc machine add root@($ip) --context ($ctx) --name ($mname)"
      ^uc machine add $"root@($ip)" --context $ctx --name $mname -i $key -y
    }
  }

  # Deploy the wildcard/DNS-01 Caddy ingress. ONE *.<domain> cert via Cloudflare
  # DNS-01 covers every subdomain — no HTTP-01, no waiting, no rate-limit churn.
  # DOMAIN + CLOUDFLARE_API_TOKEN are injected here (token already in env via fnox).
  if ($domain | is-not-empty) {
    print $"==> Deploying wildcard Caddy \(DNS-01 cert for ($wildcard)\)"
    with-env { DOMAIN: $domain } { ^uc deploy -f caddy/compose.yaml -y }
  }

  # Record an 'up' event in the ledger (best-effort). Omit --fqdns when empty:
  # nushell drops empty-string flag values when invoking a script.
  do {
    let base = [up --cluster $ctx --ips ($ips | str join ",") --server-type $out.server_type.value --location $out.location.value]
    let args = (if ($wildcard | is-empty) { $base } else { $base | append [--fqdns $wildcard] })
    nu state/log.nu ...$args
  } | ignore

  print ""
  print "Cluster is up. Next:"
  if ($domain | is-not-empty) {
    print $"  publish any subdomain — it resolves \(($wildcard)\) and gets the wildcard cert instantly:"
    print $"  uc run -p app.($domain):8000/https traefik/whoami"
  }
  print "  mise run deploy    # apply compose.yaml"
  print "  mise run status"
}
