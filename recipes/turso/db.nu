#!/usr/bin/env nu
# Manage the SQLite databases (namespaces) on the turso/libSQL server.
#
#   mise run turso:db:list             # list databases
#   mise run turso:db:create <name>    # create a new database
#   mise run turso:db:delete <name>    # delete a database (DESTRUCTIVE)
#
# Each database is an isolated SQLite db with its OWN bottomless backup in R2
# (verified). Apps address it by Host subdomain: a client pointed at
# `http://<name>.<host>` (Host header `<name>.…`) targets that database; the
# bare host targets the `default` database.
#
# The admin API binds the uncloud overlay only (never public), so these run
# IN-CLUSTER. Override the endpoint with TURSO_ADMIN_URL (default the overlay
# service name). For local dev against `recipe:local`, port-forward 9090 and set
# TURSO_ADMIN_URL=http://localhost:9090.
# The admin API has no "list all" endpoint, so the database inventory comes from
# the R2 backups — `mise run turso:db:list` runs `dr.nu list` for that.
def admin [] { $env.TURSO_ADMIN_URL? | default "http://sqld:9090" }

def main [] {
  print -e "turso db — create <name> | delete <name>   (inventory: mise run turso:db:list)"
}

def "main create" [name: string] {
  if ($name == "default") { print -e "the 'default' database already exists."; return }
  http post -t application/json $"(admin)/v1/namespaces/($name)/create" {}
  print $"✅ created database '($name)'. Address it via Host '($name).<host>'; it now backs up to R2 under ns-*:($name)."
}

def "main delete" [name: string] {
  if ($name == "default") { print -e "refusing to delete the 'default' database."; return }
  http delete $"(admin)/v1/namespaces/($name)"
  print $"🗑  deleted database '($name)' (its R2 backup generations remain until pruned)."
}
