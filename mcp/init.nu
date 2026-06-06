# Startup config for the MCP server (`mcp:serve` = `nu --mcp`) and the yoke AI
# driver (`ai:ask`). Loaded via --config, so every LLM nu-tool call + MCP
# `evaluate` sees these wrappers. CWD is the repo root.
#
# Friendly read-only views over the vm-uncloud control plane — the AI/MCP actor
# gets the same picture as the web GUI, by calling these instead of memorising
# hcloud/uc/tofu invocations. All shell out (no module resolution issues).

# Hetzner nodes (all contexts).
def uncloud-nodes [] { ^fnox exec --if-missing ignore -- hcloud server list -o json | from json }

# uncloud services on the current context.
def uncloud-services [] { ^uc ls }

# Hetzner snapshots (Windows state images, etc.).
def uncloud-snapshots [] { ^fnox exec --if-missing ignore -- hcloud image list --type snapshot -o json | from json }

# Deploy/lifecycle ledger.
def uncloud-ledger [] {
  let p = "state/log.jsonl"
  if ($p | path exists) { open $p | lines | where ($it | str trim | is-not-empty) | each {|l| $l | from json } } else { [] }
}

# Cost model (provider/SKU pricing).
def uncloud-costs [] {
  open state/costs.jsonl | lines | where ($it | str trim | is-not-empty) | each {|l| $l | from json }
}
