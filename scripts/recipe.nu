#!/usr/bin/env nu
# Deploy a recipe by name. Looks in this repo's committed examples/ first, then
# falls back to the upstream catalog in recipes.toml (cloned into .src/).
#
#   mise run recipe wordpress     # local example, hostname auto-derived
#   mise run recipe nats          # upstream catalog
#   mise run recipe               # list everything available
#
# Records a deploy event in state/log.jsonl.

use r2.nu *

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

# wordpress.<domain> from tofu state, unless WP_DOMAIN is set explicitly.
def wp_domain [] {
  let explicit = ($env.WP_DOMAIN? | default "")
  if ($explicit | is-not-empty) { return $explicit }
  let d = (^tofu -chdir=tofu output -raw domain | complete)
  if ($d.exit_code == 0) {
    let dom = ($d.stdout | str trim)
    if ($dom | is-not-empty) { return $"wordpress.($dom)" }
  }
  ""
}

def main [recipe?: string] {
  load-env (r2-creds)   # so `tofu output` can read remote state
  # Sync upstream only if the recipe isn't a local example (saves a clone).
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

  # Per-recipe env wiring.
  let envs = (if ($recipe | str starts-with "wordpress") {
    let domain = (wp_domain)
    if ($domain | is-empty) {
      print "ERROR: no domain found. Either bring up a cluster with a domain (mise run up),"
      print "       or set WP_DOMAIN=host.example.com explicitly."
      exit 1
    }
    print $"==> WordPress will be published at https://($domain)"
    {
      WP_DOMAIN: $domain
      DB_USER: "wordpress"
      DB_NAME: "wordpress"
      DB_PASSWORD: (random chars --length 24)
      DB_ROOT_PASSWORD: (random chars --length 24)
    }
  } else { {} })

  print $"==> uc deploy -f ($compose) -y"
  with-env $envs { ^uc deploy -f $compose -y }

  # Ledger (best-effort). Omit --host when empty.
  let cluster = ($env.UNCLOUD_CONTEXT? | default "")
  let host = ($envs.WP_DOMAIN? | default "")
  do {
    let base = [deploy --cluster $cluster --service $recipe]
    let args = (if ($host | is-empty) { $base } else { $base | append [--host $host] })
    nu state/log.nu ...$args
  } | ignore

  print ""
  print "Deployed. Check: mise run status"
}
