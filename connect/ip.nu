#!/usr/bin/env nu
# Resolve the public IPv4 of the Windows desktop node. Defaults to the
# win-batch node name; override with WIN_NODE for a differently-named node.
# Used by the rdp:* / viewer tasks.

def main [] {
  let node = ($env.WIN_NODE? | default "win-batch-1")
  ^fnox exec --if-missing ignore -- hcloud server ip $node | str trim
}
