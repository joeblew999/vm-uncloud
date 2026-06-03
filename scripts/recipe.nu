#!/usr/bin/env nu
# Deploy a recipe by name. Resolves the repo's committed examples/ first, then
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

# Find <recipe>/compose.yaml: committed examples/ first, then synced sources.
def find_recipe [recipe: string] {
  let local = $"examples/($recipe)/compose.yaml"
  if ($local | path exists) { return $local }
  for s in (sources) {
    let c = $".src/($s.name)/($recipe)/compose.yaml"
    if ($c | path exists) { return $c }
  }
  ""
}

def list_recipes [] {
  print "  [examples] (this repo)"
  if ("examples" | path exists) {
    ls examples | where type == dir | get name | path basename
      | where {|n| ($"examples/($n)/compose.yaml" | path exists)} | each {|n| print $"    - ($n)"}
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

def main [recipe?: string] {
  load-env (r2-creds)   # so `tofu output` can read remote state
  if ($recipe | is-not-empty) and not ($"examples/($recipe)/compose.yaml" | path exists) {
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
    print $"ERROR: recipe '($recipe)' not found in examples/ or any source. Available:"
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

  print $"==> uc deploy -f ($compose) -y"
  with-env $envs { ^uc deploy -f $compose -y }

  let cluster = ($env.UNCLOUD_CONTEXT? | default "")
  do {
    let base = [deploy --cluster $cluster --service $recipe]
    let args = (if ($host | is-empty) { $base } else { $base | append [--host $host] })
    nu state/log.nu ...$args
  } | ignore

  print ""
  print "Deployed. Check: mise run status"
}
