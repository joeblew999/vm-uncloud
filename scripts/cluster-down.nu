#!/usr/bin/env nu
# Tear everything down: destroys the Hetzner server(s) + any Cloudflare DNS
# records this repo created, then prunes the now-dead local uncloud context
# (there's no `uncloud ctx rm`, so we edit the config file directly).
#
# Non-interactive: set FORCE=1 (or UNCLOUD_AUTO_CONFIRM=1) to skip the prompt.

use r2.nu *

const TOFU = ["-chdir=tofu"]

# --context tears down a non-default node class (its own workspace + tfvars +
# uncloud context). Omit for the default cluster. e.g.
#   mise run cluster:down -- --context win-batch
def main [--context: string = "", --yes] {   # --yes / FORCE=1 skips the prompt (headless)
  load-env (r2-creds)   # R2 state creds (no-op for local state)

  let alt = ($context | is-not-empty)
  let varfile = (if $alt { [$"-var-file=($context).tfvars"] } else { [] })
  # Select the matching workspace so we destroy the right state, not the cluster.
  let ws = (if $alt { $context } else { "default" })
  do { ^tofu ...$TOFU workspace select $ws } | complete | ignore

  let forced = $yes or (($env.FORCE? | default "") != "") or (($env.UNCLOUD_AUTO_CONFIRM? | default "") != "")
  if not $forced {
    let expected = (^tofu ...$TOFU output -raw cluster_name | complete | get stdout | str trim)
    let expected = (if ($expected | is-empty) { "uncloud" } else { $expected })
    # input fails with a cryptic I/O error when there's no TTY — give a useful hint.
    let answer = (try { input $"Type the cluster name to confirm destroy \(($expected)\): " } catch { print -e "✗ no TTY to confirm — rerun headless: mise run cluster:down -- --yes"; exit 1 })
    if $answer != $expected { print "Aborted."; exit 1 }
  }

  print "==> tofu destroy"
  ^tofu ...$TOFU destroy -auto-approve -input=false ...$varfile

  # Prune the local uncloud context that pointed at the destroyed machine.
  let ctx = (if $alt { $context } else { ($env.UNCLOUD_CONTEXT? | default "") })
  if ($ctx | is-not-empty) { do { nu state/log.nu down --cluster $ctx } | ignore }
  let cfg = ($nu.home-dir | path join ".config" "uncloud" "config.yaml")
  if ($ctx | is-not-empty) and ($cfg | path exists) {
    let data = (open $cfg)
    if ($ctx in ($data.contexts? | default {} | columns)) {
      let pruned = ($data | update contexts {|d| $d.contexts | reject $ctx})
      let pruned = (if (($pruned.current_context? | default "") == $ctx) { $pruned | upsert current_context "" } else { $pruned })
      $pruned | to yaml | save -f $cfg
      print $"==> Pruned local uncloud context '($ctx)'."
    }
  }

  print ""
  print "Teardown complete — servers, DNS records, and local context removed."
}
