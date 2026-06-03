#!/usr/bin/env nu
# Tear everything down: destroys the Hetzner server(s) + any Cloudflare DNS
# records this repo created, then prunes the now-dead local uncloud context
# (there's no `uc ctx rm`, so we edit the config file directly).
#
# Non-interactive: set FORCE=1 (or UNCLOUD_AUTO_CONFIRM=1) to skip the prompt.

const TOFU = ["-chdir=tofu"]

def main [] {
  let forced = (($env.FORCE? | default "") != "") or (($env.UNCLOUD_AUTO_CONFIRM? | default "") != "")
  if not $forced {
    let expected = (^tofu ...$TOFU output -raw cluster_name | complete | get stdout | str trim)
    let expected = (if ($expected | is-empty) { "uncloud" } else { $expected })
    let answer = (input $"Type the cluster name to confirm destroy \(($expected)\): ")
    if $answer != $expected { print "Aborted."; exit 1 }
  }

  print "==> tofu destroy"
  ^tofu ...$TOFU destroy -auto-approve -input=false

  # Prune the local uncloud context that pointed at the destroyed machine.
  let ctx = ($env.UNCLOUD_CONTEXT? | default "")
  if ($ctx | is-not-empty) { do { nu state/log.nu down --cluster $ctx } | ignore }
  let cfg = ($nu.home-path | path join ".config" "uncloud" "config.yaml")
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
