#!/usr/bin/env nu
# Provision Hetzner + (optional) Cloudflare DNS via OpenTofu, then turn each
# server into an Uncloud machine over SSH. Idempotent — re-running reconciles.
#
# Tokens (HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN) are injected by `fnox exec` from
# the keychain; the tofu providers read them straight from the environment.
# SSH key comes from tofu (var ssh_private_key_file, set in terraform.tfvars).

use r2.nu *

const TOFU = ["-chdir=tofu"]

# `uc machine init/add`'s readiness spinner opens /dev/tty directly, so it dies
# in a shell with no controlling terminal (CI, agents) even with -y. Verified
# fix: give it a PTY. macOS/BSD: `script -q /dev/null <cmd…>`; Linux:
# `script -qec "<cmd>" /dev/null`. Upstream: psviderski/uncloud#386.
def with-pty [cmd: list<string>] {
  if $nu.os-info.name == "macos" {
    ^script -q /dev/null ...$cmd
  } else {
    ^script -qec ($cmd | str join " ") /dev/null
  }
}

# --context selects a node class with ISOLATED state: a tofu workspace named
# <context> + tofu/<context>.tfvars + an uncloud context of the same name. Omit
# it for the default cluster (workspace "default", terraform.tfvars, context
# from $UNCLOUD_CONTEXT). e.g. `mise run up -- --context win-batch`.
def main [--context: string = ""] {
  # If remote (R2) state is active, derive its S3 creds from the CF token so
  # every tofu command below can read/write state. No-op for local state.
  load-env (r2-creds)

  let alt = ($context | is-not-empty)
  let varfile = (if $alt { [$"-var-file=($context).tfvars"] } else { [] })

  if not ("tofu/terraform.tfvars" | path exists) {
    print "ERROR: tofu/terraform.tfvars not found."
    print "       cp tofu/terraform.tfvars.example tofu/terraform.tfvars and edit it."
    exit 1
  }
  if $alt and not ($"tofu/($context).tfvars" | path exists) {
    print $"ERROR: tofu/($context).tfvars not found \(needed for --context ($context)\)."
    print $"       cp tofu/($context).tfvars.example tofu/($context).tfvars and edit it."
    exit 1
  }

  print "==> tofu init"
  ^tofu ...$TOFU init -input=false

  # Isolate state per context via a workspace (default cluster = "default").
  let ws = (if $alt { $context } else { "default" })
  let sel = (do { ^tofu ...$TOFU workspace select $ws } | complete)
  if $sel.exit_code != 0 { ^tofu ...$TOFU workspace new $ws }
  print $"==> tofu workspace: ($ws)"

  # tofu apply blocks until the box is fully READY: its remote-exec provisioner
  # waits for SSH (native connection retry) then `cloud-init status --wait`.
  # No sleep/poll here — when this returns, the machine is ready for init.
  print "==> tofu apply (server + DNS + waits for cloud-init via provisioner)"
  ^tofu ...$TOFU apply -auto-approve -input=false ...$varfile

  let out = (^tofu ...$TOFU output -json | from json)
  let ips = ($out.node_ipv4.value)
  let domain = ($out.domain.value)
  let wildcard = ($out.wildcard.value)
  print $"==> Servers: ($ips | str join ', ')"
  if ($domain | is-not-empty) { print $"==> Wildcard: ($wildcard) -> ($ips | get 0)" }

  let key = ($out.ssh_private_key_file.value | path expand)
  # Load the key into the ssh-agent so `uc machine init` can key-auth as root.
  # A fresh shell/agent may be empty → init silently hangs on a password prompt.
  # Idempotent (re-adding an already-loaded key is a no-op).
  do { ^ssh-add $key } | complete | ignore
  # Clear stale host keys (Hetzner recycles IPs) so client-side `uc machine init`
  # doesn't trip on a mismatched known_hosts entry. One-shot, not a poll.
  for ip in $ips { ^ssh-keygen -R $ip out+err> /dev/null }

  # Context name MUST match $UNCLOUD_CONTEXT — `uc machine init` does NOT read
  # that env var (it defaults the new context to "default"), so we pass it
  # explicitly. Otherwise deploy/recipe/down would look for a context the init
  # step never created.
  let ctx = (if $alt { $context } else { ($env.UNCLOUD_CONTEXT? | default "hetzner") })

  # When we have a domain we deploy our own wildcard/DNS-01 Caddy below, so skip
  # the default Caddy at init time (--no-caddy). --no-dns: we manage DNS via
  # Cloudflare, not the uncld.dev rental.
  let caddy_flag = (if ($domain | is-empty) { [] } else { ["--no-caddy"] })

  # First node initialises the cluster; the rest join the WireGuard mesh.
  # Wrapped in with-pty so the readiness spinner doesn't need a real TTY.
  $ips | enumerate | each {|row|
    let ip = $row.item
    let mname = $"($ctx)-($row.index + 1)"
    if $row.index == 0 {
      print $"==> uc machine init root@($ip) --context ($ctx) --name ($mname) --no-dns"
      with-pty (["uc" "machine" "init" $"root@($ip)" "--context" $ctx "--name" $mname "--no-dns"] ++ $caddy_flag ++ ["-i" $key "-y"])
    } else {
      print $"==> uc machine add root@($ip) --context ($ctx) --name ($mname)"
      with-pty ["uc" "machine" "add" $"root@($ip)" "--context" $ctx "--name" $mname "-i" $key "-y"]
    }
  }

  # Deploy the wildcard/DNS-01 Caddy ingress. ONE *.<domain> cert via Cloudflare
  # DNS-01 covers every subdomain — no HTTP-01, no waiting, no rate-limit churn.
  # DOMAIN + CLOUDFLARE_API_TOKEN are injected here (token already in env via fnox).
  # Windows nodes have no wildcard (wildcard output is empty) — they serve RDP,
  # not web, so no Caddy ingress.
  if ($wildcard | is-not-empty) {
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
