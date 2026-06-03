#!/usr/bin/env nu
# Deploy a ready-made recipe by name, searching every source in recipes.toml.
#
#   mise run recipe wordpress-mariadb       # needs WP_DOMAIN (a hostname you A-recorded)
#   mise run recipe nats
#   mise run recipe                         # lists all available recipes
#
# Syncs the source repos into .src/ on first use, injects any required env,
# then `uc deploy -y` from the recipe folder (uncloud resolves the recipe's
# relative .env / config files), and records a deploy event in state/log.jsonl.

def sources [] {
  if not ("recipes.toml" | path exists) { return [] }
  (open recipes.toml | get sources? | default [])
}

# Find <recipe>/compose.yaml across all synced sources; return its path or "".
def find_recipe [recipe: string] {
  for s in (sources) {
    let compose = $".src/($s.name)/($recipe)/compose.yaml"
    if ($compose | path exists) { return $compose }
  }
  ""
}

def list_recipes [] {
  for s in (sources) {
    let root = $".src/($s.name)"
    if ($root | path exists) {
      print $"  [($s.name)]"
      ls $root | where type == dir | get name | path basename
        | where {|n| ($"($root)/($n)/compose.yaml" | path exists)}
        | each {|n| print $"    - ($n)"}
    }
  }
}

def main [recipe?: string] {
  nu scripts/recipes-sync.nu
  if ($recipe | is-empty) {
    print "Usage: mise run recipe <name>. Available recipes:"
    list_recipes
    exit 1
  }

  let compose = (find_recipe $recipe)
  if ($compose | is-empty) {
    print $"ERROR: recipe '($recipe)' not found in any source. Available:"
    list_recipes
    exit 1
  }

  # Per-recipe env. Add cases here as you adopt more recipes that need config.
  let envs = (match $recipe {
    "wordpress-mariadb" => {
      let domain = ($env.WP_DOMAIN? | default "")
      if ($domain | is-empty) {
        print "ERROR: set WP_DOMAIN to any subdomain under your domain (the wildcard covers it), e.g."
        print "  WP_DOMAIN=wordpress.amplifycms.net mise run recipe wordpress-mariadb"
        exit 1
      }
      {
        WP_DOMAIN: $domain
        DB_USER: "wordpress"
        DB_NAME: "wordpress"
        DB_PASSWORD: (random chars --length 24)
        DB_ROOT_PASSWORD: (random chars --length 24)
      }
    }
    _ => {}
  })

  print $"==> uc deploy -f ($compose) -y"
  with-env $envs { ^uc deploy -f $compose -y }

  # Record in the ledger (best-effort). Omit --host when empty (nushell drops
  # empty-string flag values passed to a script).
  let cluster = ($env.UNCLOUD_CONTEXT? | default "")
  let host = ($env.WP_DOMAIN? | default "")
  do {
    let base = [deploy --cluster $cluster --service $recipe]
    let args = (if ($host | is-empty) { $base } else { $base | append [--host $host] })
    nu state/log.nu ...$args
  } | ignore

  print ""
  print "Deployed. Check: mise run status"
}
