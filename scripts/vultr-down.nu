#!/usr/bin/env nu
# Destroy the win-kvm Vultr Bare Metal node and prune its local uncloud context.
#
# NOTE: Vultr BM has no native hot-snapshot. vm-servers preserved Windows state
# via an R2 transit pipeline (dd|gzip→R2→snapshot create-url); that path is NOT
# yet ported here, so win-kvm teardown currently does NOT preserve Windows state.
# For state-preserving on-demand Windows today, use win-batch (Hetzner snapshot).

def main [] {
  let label = ($env.VULTR_LABEL? | default "win-kvm")
  let out = (^fnox exec --if-missing ignore -- vultr-cli bare-metal list -o json | complete)
  let bms = (try { $out.stdout | from json | get bare_metals? | default [] } catch { [] })
  let match = ($bms | where label == $label)
  if ($match | is-empty) { print $"no Vultr BM labelled '($label)' — nothing to destroy"; return }
  let id = ($match | first | get id)

  print $"destroying Vultr BM '($label)' (id ($id))"
  ^fnox exec --if-missing ignore -- vultr-cli bare-metal delete $id
  do { nu state/log.nu down --cluster win-kvm } | ignore

  # Prune the local uncloud context, if present.
  let cfg = ($nu.home-dir | path join ".config" "uncloud" "config.yaml")
  if ($cfg | path exists) {
    let data = (open $cfg)
    if ("win-kvm" in ($data.contexts? | default {} | columns)) {
      let pruned = ($data | update contexts {|d| $d.contexts | reject "win-kvm"})
      let pruned = (if (($pruned.current_context? | default "") == "win-kvm") { $pruned | upsert current_context "" } else { $pruned })
      $pruned | to yaml | save -f $cfg
      print "pruned local uncloud context 'win-kvm'."
    }
  }
  print "win-kvm node destroyed."
}
