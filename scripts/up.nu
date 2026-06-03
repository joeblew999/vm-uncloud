#!/usr/bin/env nu
# Provision Hetzner + (optional) Cloudflare DNS via OpenTofu, then turn each
# server into an Uncloud machine over SSH. Idempotent — re-running reconciles.
#
# Tokens (HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN) are injected by `fnox exec` from
# the keychain; the tofu providers read them straight from the environment.
# SSH uses $SSH_KEY_FILE (default ~/.ssh/gedw99_hetzner).

const TOFU = ["-chdir=tofu"]

def ssh_key_file [] {
  ($env.SSH_KEY_FILE? | default "~/.ssh/gedw99_hetzner" | path expand)
}

def main [] {
  if not ("tofu/terraform.tfvars" | path exists) {
    print "ERROR: tofu/terraform.tfvars not found."
    print "       cp tofu/terraform.tfvars.example tofu/terraform.tfvars and edit it."
    exit 1
  }

  print "==> tofu init"
  ^tofu ...$TOFU init -input=false

  print "==> tofu apply (Hetzner server + cloud-init + Cloudflare DNS)"
  ^tofu ...$TOFU apply -auto-approve -input=false

  let out = (^tofu ...$TOFU output -json | from json)
  let ips = ($out.node_ipv4.value)
  let fqdns = ($out.fqdns.value)
  print $"==> Servers: ($ips | str join ', ')"
  if ($fqdns | is-not-empty) { print $"==> Domains: ($fqdns | str join ', ')" }

  let key = (ssh_key_file)
  for ip in $ips { prepare_host $ip $key }

  # Context name MUST match $UNCLOUD_CONTEXT — `uc machine init` does NOT read
  # that env var (it defaults the new context to "default"), so we pass it
  # explicitly. Otherwise deploy/recipe/down would look for a context the init
  # step never created.
  let ctx = ($env.UNCLOUD_CONTEXT? | default "hetzner")

  # First node initialises the cluster; the rest join the WireGuard mesh.
  # --no-dns: we manage DNS ourselves via Cloudflare, so skip the uncld.dev rental.
  $ips | enumerate | each {|row|
    let ip = $row.item
    let mname = $"($ctx)-($row.index + 1)"
    if $row.index == 0 {
      print $"==> uc machine init root@($ip) --context ($ctx) --name ($mname) --no-dns"
      ^uc machine init $"root@($ip)" --context $ctx --name $mname --no-dns -i $key -y
    } else {
      print $"==> uc machine add root@($ip) --context ($ctx) --name ($mname)"
      ^uc machine add $"root@($ip)" --context $ctx --name $mname -i $key -y
    }
  }

  # Record an 'up' event in the ledger (best-effort). Omit --fqdns when empty:
  # nushell drops empty-string flag values when invoking a script.
  let fqstr = ($fqdns | str join ",")
  do {
    let base = [up --cluster $ctx --ips ($ips | str join ",") --server-type $out.server_type.value --location $out.location.value]
    let args = (if ($fqstr | is-empty) { $base } else { $base | append [--fqdns $fqstr] })
    nu state/log.nu ...$args
  } | ignore

  print ""
  print "Cluster is up. Next:"
  if ($fqdns | is-not-empty) {
    print $"  uc run -p ($fqdns | get 0):8000/https traefik/whoami"
  }
  print "  mise run deploy    # apply compose.yaml"
  print "  mise run status"
}

# Clear stale host keys (Hetzner recycles IPs), wait for SSH, then wait for
# cloud-init to finish installing the uncloud daemon.
def prepare_host [ip: string, key: string] {
  ^ssh-keygen -R $ip out+err> /dev/null

  print $"==> Waiting for SSH on ($ip)..."
  mut tries = 0
  loop {
    let ok = (do {
      ^ssh -i $key -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5 $"root@($ip)" true
    } | complete | get exit_code) == 0
    if $ok { break }
    $tries = $tries + 1
    if $tries >= 30 { print $"    WARNING: SSH to ($ip) not ready after ~5min."; return }
    sleep 10sec
  }

  print $"==> Waiting for cloud-init to finish on ($ip)..."
  ^ssh -i $key -o StrictHostKeyChecking=no $"root@($ip)" "cloud-init status --wait || true" out+err> /dev/null
  print $"    ($ip) ready."
}
