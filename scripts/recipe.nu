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

# wordpress.<domain> from the cluster's single source of truth, unless WP_DOMAIN
# is set explicitly.
def wp_domain [] {
  let explicit = ($env.WP_DOMAIN? | default "")
  if ($explicit | is-not-empty) { return $explicit }
  let dom = (cluster-domain)
  if ($dom | is-empty) { "" } else { $"wordpress.($dom)" }
}

# n-char hex string, for signing keys.
def randhex [n: int] {
  let h = ["0" "1" "2" "3" "4" "5" "6" "7" "8" "9" "a" "b" "c" "d" "e" "f"]
  (1..$n | each {|_| $h | get (random int 0..15) } | str join)
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

  # DOMAIN is injected for any recipe whose compose uses ${DOMAIN}.
  let dom = (cluster-domain)
  mut envs = (if ($dom | is-empty) { {} } else { { DOMAIN: $dom } })
  mut host = ""   # public hostname, for the ledger

  # Per-recipe env wiring.
  if ($recipe | str starts-with "wordpress") {
    let wd = (wp_domain)
    if ($wd | is-empty) {
      print "ERROR: no domain. Run 'mise run up' first, or set WP_DOMAIN=host.example.com."
      exit 1
    }
    $host = $wd
    $envs = ($envs | merge {
      WP_DOMAIN: $wd, DB_USER: "wordpress", DB_NAME: "wordpress",
      DB_PASSWORD: (random chars --length 24), DB_ROOT_PASSWORD: (random chars --length 24)
    })
  } else if ($recipe == "imgproxy") {
    if ($dom | is-empty) { print "ERROR: no domain. Run 'mise run up' first (imgproxy publishes on img.<domain>)."; exit 1 }
    $host = $"img.($dom)"
    let key = ($env.IMGPROXY_KEY? | default (randhex 64))
    let salt = ($env.IMGPROXY_SALT? | default (randhex 64))
    print $"==> imgproxy signing key:  ($key)"
    print $"==> imgproxy signing salt: ($salt)"
    print "    save these — you need them to sign image URLs"
    $envs = ($envs | merge { IMGPROXY_KEY: $key, IMGPROXY_SALT: $salt })
  }
  if ($host | is-not-empty) { print $"==> publishing at https://($host)" }

  print $"==> uc deploy -f ($compose) -y"
  with-env $envs { ^uc deploy -f $compose -y }

  # Ledger (best-effort). Omit --host when empty. Copy to immutables — a closure
  # can't capture `mut` vars.
  let cluster = ($env.UNCLOUD_CONTEXT? | default "")
  let pub = $host
  do {
    let base = [deploy --cluster $cluster --service $recipe]
    let args = (if ($pub | is-empty) { $base } else { $base | append [--host $pub] })
    nu state/log.nu ...$args
  } | ignore

  print ""
  print "Deployed. Check: mise run status"
}
