#!/usr/bin/env nu
# Resolve the public IPv4 of the Windows desktop node, for the rdp:* / viewer
# tasks. Dispatches on WIN_PROVIDER:
#   hetzner (default) → hcloud server ip $WIN_NODE   (win-batch, e.g. win-batch-1)
#   vultr             → the Vultr BM matching $VULTR_LABEL   (win-kvm)

def main [] {
  let provider = ($env.WIN_PROVIDER? | default "hetzner")
  match $provider {
    "hetzner" => {
      let node = ($env.WIN_NODE? | default "win-batch-1")
      ^fnox exec --if-missing ignore -- hcloud server ip $node | str trim
    }
    "vultr" => {
      let label = ($env.VULTR_LABEL? | default "win-kvm")
      let out = (^fnox exec --if-missing ignore -- vultr-cli bare-metal list -o json | complete)
      if $out.exit_code != 0 { return "" }
      let bms = (try { $out.stdout | from json | get bare_metals? | default [] } catch { [] })
      ($bms | where label == $label | get main_ip? | default [] | first | default "" | str trim)
    }
    _ => { print -e $"WIN_PROVIDER must be hetzner|vultr (got '($provider)')"; "" }
  }
}
