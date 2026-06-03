#!/usr/bin/env nu
# Deploy a ready-made recipe from psviderski/uncloud-recipes.
#
#   mise run recipe wordpress-mariadb       # needs WP_DOMAIN (a hostname you A-recorded)
#   mise run recipe nats
#   mise run recipe postgres
#
# Clones the recipes into .src/ on first use, injects any required env, then
# `uc deploy -y` from the recipe folder (uncloud resolves the recipe's relative
# .env / config files for us).

def main [recipe?: string] {
  if ($recipe | is-empty) {
    print "Usage: mise run recipe <name>   (e.g. wordpress-mariadb, nats, postgres)"
    print "Available recipes:"
    if (".src/uncloud-recipes" | path exists) {
      ls .src/uncloud-recipes | where type == dir | get name | path basename | each {|n| print $"  - ($n)"}
    } else { print "  (run any recipe to fetch the list)" }
    exit 1
  }

  nu scripts/recipes-sync.nu
  let dir = $".src/uncloud-recipes/($recipe)"
  let compose = $"($dir)/compose.yaml"
  if not ($compose | path exists) {
    print $"ERROR: no compose.yaml for recipe '($recipe)' at ($compose)"
    exit 1
  }

  # Per-recipe env. Add cases here as you adopt more recipes.
  let envs = (match $recipe {
    "wordpress-mariadb" => {
      let domain = ($env.WP_DOMAIN? | default "")
      if ($domain | is-empty) {
        print "ERROR: set WP_DOMAIN to a hostname you created in app_hostnames, e.g."
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
  print ""
  print "Deployed. Check: mise run status"
}
