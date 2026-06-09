#!/usr/bin/env nu
# Deploy a recipe by name. Resolves the repo's committed recipes/ first, then
# the upstream catalog in recipes.toml (cloned into .src/).
#
#   mise run recipe wordpress     # local example
#   mise run recipe imaginary     # local example
#   mise run recipe nats          # upstream catalog
#   mise run recipe               # list everything
#
# This script is GENERIC — it has no per-recipe knowledge. A recipe that needs
# config (generated secrets, a derived hostname) ships a `prepare.nu` next to its
# compose.yaml. recipe.nu runs it with DOMAIN in the env; prepare.nu prints a JSON
# object of env vars on stdout (merged into the deploy) and human notes on stderr.
# An optional HOST key is used for the ledger.

use r2.nu *
use cluster.nu *

def sources [] {
  if not ("recipes.toml" | path exists) { return [] }
  (open recipes.toml | get sources? | default [])
}

# Find <recipe>/compose.yaml: committed recipes/ first, then synced sources.
def find_recipe [recipe: string] {
  let local = $"recipes/($recipe)/compose.yaml"
  if ($local | path exists) { return $local }
  for s in (sources) {
    let c = $".src/($s.name)/($recipe)/compose.yaml"
    if ($c | path exists) { return $c }
  }
  ""
}

def list_recipes [] {
  print "  [recipes] (this repo)"
  if ("recipes" | path exists) {
    ls recipes | where type == dir | get name | path basename
      | where {|n| ($"recipes/($n)/compose.yaml" | path exists)} | each {|n| print $"    - ($n)"}
  }
  for s in (sources) {
    let root = $".src/($s.name)"
    if ($root | path exists) {
      print $"  [($s.name)] (upstream)"
      ls $root | where type == dir | get name | path basename
        | where {|n| ($"($root)/($n)/compose.yaml" | path exists)} | each {|n| print $"    - ($n)"}
    }
  }
}

# --context deploys onto a non-default uncloud cluster (e.g. the win-batch node):
#   mise run recipe windows -- --context win-batch
def main [recipe?: string, --context: string = ""] {
  load-env (r2-creds)   # so `tofu output` can read remote state
  if ($recipe | is-not-empty) and not ($"recipes/($recipe)/compose.yaml" | path exists) {
    nu scripts/recipes-sync.nu
  }
  if ($recipe | is-empty) {
    nu scripts/recipes-sync.nu
    print "Usage: mise run recipe <name>. Available:"
    list_recipes
    exit 1
  }

  let compose = (find_recipe $recipe)
  if ($compose | is-empty) {
    print $"ERROR: recipe '($recipe)' not found in recipes/ or any source. Available:"
    list_recipes
    exit 1
  }
  let dir = ($compose | path dirname)

  # DOMAIN is injected for any recipe whose compose uses ${DOMAIN}.
  let dom = (cluster-domain)
  mut envs = (if ($dom | is-empty) { {} } else { { DOMAIN: $dom } })

  # Recipe-owned config: run its prepare.nu (stdout = JSON env, stderr = notes).
  let prep = $"($dir)/prepare.nu"
  if ($prep | path exists) {
    let r = (with-env { DOMAIN: $dom } { ^nu $prep } | complete)
    if (($r.stderr | str trim) != "") { print ($r.stderr | str trim) }
    if $r.exit_code != 0 { exit 1 }
    $envs = ($envs | merge ($r.stdout | from json))
  }

  let host = ($envs.HOST? | default $dom)
  if ($host | is-not-empty) { print $"==> publishing at https://($host)" }

  # Target a specific uncloud cluster when --context is given (else the current).
  let ctx_flag = (if ($context | is-not-empty) { [--context $context] } else { [] })
  print $"==> uc deploy -f ($compose) ($ctx_flag | str join ' ') -y"
  with-env $envs { ^uc deploy -f $compose ...$ctx_flag -y }

  let cluster = (if ($context | is-not-empty) { $context } else { ($env.UNCLOUD_CONTEXT? | default "") })
  do {
    let base = [deploy --cluster $cluster --service $recipe]
    let args = (if ($host | is-empty) { $base } else { $base | append [--host $host] })
    nu state/log.nu ...$args
  } | ignore

  # Best-effort: register the live URL in OrangeVault so other systems can discover
  # it (registry.nu self-guards on missing bw/creds; `| ignore` → can't break the
  # deploy). Opt-in via VMU_REGISTRY=1 until verified against a live vault.
  if ((($env.VMU_REGISTRY? | default "") == "1") and ($host | is-not-empty)) {
    do { nu scripts/registry.nu publish --context $cluster --service $recipe --url $"https://($host)" } | ignore
  }

  print ""
  print "Deployed. Check: mise run status"
}
