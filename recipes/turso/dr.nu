#!/usr/bin/env nu
# Disaster recovery for the Turso/libSQL recipe. DR is only real if it can be
# REHEARSED — these commands run on demand (e.g. weekly) against the live R2
# backup and are all READ-ONLY on R2 (list/verify/restore never mutate it):
#
#   mise run turso:dr:list      # every database + its backup generations
#   mise run turso:dr:verify    # WEEKLY DRILL: restore + integrity-check EVERY db
#   mise run turso:dr:restore   # pull one db to a local file (recovery / PITR)
#
# The recipe runs sqld with namespaces enabled, so ONE server holds many isolated
# SQLite databases, each backed up under its own R2 prefix `ns-<db-id>:<name>`
# (db-id = TURSO_DB_ID, name = the namespace; the single-db default is `default`).
# These tasks enumerate every database from R2 and act on each — so the drill
# covers the whole fleet, and works even when the cluster itself is down (DR!).
#
# Creds are derived from CLOUDFLARE_API_TOKEN like the recipe + tofu backend
# (scripts/r2.nu); tasks run under `fnox exec` so the token is in the env.
use ../../scripts/r2.nu *

const IMG = "ghcr.io/tursodatabase/libsql-server:latest"
const MC  = "minio/mc"

def bucket [] { $env.TURSO_BUCKET? | default "vm-uncloud-turso" }
def db []     { $env.TURSO_DB_ID? | default "vmu-turso" }
# bottomless-cli targets a database via `-n`, which MUST be the full prefix
# `ns-<db-id>:<namespace>` (start with ns-, include the namespace). Verified.
def nsref [namespace: string] { $"ns-(db):($namespace)" }

# Run bottomless-cli in a throwaway container, configured via the same
# LIBSQL_BOTTOMLESS_* env the sqld server uses (the CLI reads creds/region/
# bucket/endpoint from these). Returns {stdout,stderr,exit_code}.
def bcli [args: list<string>, --extra-run: list<string> = []] {
  let creds = (r2-derive)
  let ep = (r2-endpoint)
  (^docker run --rm
    -e $"LIBSQL_BOTTOMLESS_BUCKET=(bucket)"
    -e $"LIBSQL_BOTTOMLESS_ENDPOINT=($ep)"
    -e $"LIBSQL_BOTTOMLESS_AWS_ACCESS_KEY_ID=($creds.AWS_ACCESS_KEY_ID)"
    -e $"LIBSQL_BOTTOMLESS_AWS_SECRET_ACCESS_KEY=($creds.AWS_SECRET_ACCESS_KEY)"
    -e $"LIBSQL_BOTTOMLESS_AWS_DEFAULT_REGION=($creds.AWS_DEFAULT_REGION)"
    ...$extra_run
    --entrypoint bottomless-cli $IMG ...$args | complete)
}

# Enumerate every database (namespace) that has a backup in R2, by listing the
# top-level `ns-<db-id>:<name>-<generation>/` prefixes and parsing the name.
# Uses the mc S3 client (works against R2) — offline-capable, no live cluster.
def namespaces [] {
  let creds = (r2-derive)
  let ep = (r2-endpoint)
  # sh redirects (NOT nushell syntax) inside the container script.
  let script = $"mc alias set r2 ($ep) ($creds.AWS_ACCESS_KEY_ID) ($creds.AWS_SECRET_ACCESS_KEY) --api S3v4 >/dev/null 2>&1; mc ls r2/(bucket)/"
  let r = (^docker run --rm --entrypoint sh $MC -c $script | complete)
  # mc ls lines look like: `[2026-… UTC]   0B ns-<db>:<name>-<gen-uuid>/` — the
  # prefix is the LAST whitespace token, not the line start.
  $r.stdout | lines
    | each {|l| $l | split row -r '\s+' | where ($it != "") | last }
    | where ($it | str starts-with $"ns-(db):")
    | each {|tok|
        let body = ($tok | str trim --char '/' | split row $"ns-(db):" | last)
        $body | parse --regex '^(?<ns>.+)-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' | get ns?.0?
      }
    | where ($it != null) | uniq
}

def hdr [m: string] { print -e $"── ($m) ─ bucket=(bucket) db-id=(db)" }

def main [] {
  print -e "turso DR — list | verify | restore"
  print -e "  mise run turso:dr:list | turso:dr:verify | turso:dr:restore"
}

# List every database and how many backup generations each has.
def "main list" [] {
  hdr "DR list"
  let ns = (namespaces)
  if ($ns | is-empty) { print "no databases backed up yet."; return }
  for n in $ns {
    let r = (bcli [-n (nsref $n) ls])
    let gens = ($r.stdout | lines | where ($it =~ '[0-9a-f]{8}-[0-9a-f]{4}') | length)
    print $"  ($n)  — ($gens) generation\(s)"
  }
}

# THE WEEKLY DRILL. Verifies EVERY database (or one via --namespace) actually
# restores and passes an integrity check. Read-only on R2. Exits non-zero if ANY
# database fails — so it can gate a scheduled job / CI.
def "main verify" [
  --namespace: string = ""   # just this db (default: all)
  --generation: string = ""
  --utc-time: string = ""
] {
  hdr "DR VERIFY (weekly drill)"
  let targets = (if ($namespace | is-not-empty) { [$namespace] } else { (namespaces) })
  if ($targets | is-empty) { print "no databases backed up yet — nothing to verify."; return }
  mut failed = []
  for n in $targets {
    mut args = [-n (nsref $n) verify]
    if ($generation | is-not-empty) { $args = ($args | append [-g $generation]) }
    if ($utc_time  | is-not-empty) { $args = ($args | append [-u $utc_time]) }
    let r = (bcli $args)
    let ok = ($r.exit_code == 0 and ($r.stdout | str contains "Verification: ok"))
    if $ok {
      print $"  ✅ ($n) — restores + integrity ok"
    } else {
      print $"  ❌ ($n) — FAILED"
      if ($r.stderr | str trim | is-not-empty) { print -e ($r.stderr | str trim) }
      $failed = ($failed | append $n)
    }
  }
  if ($failed | is-empty) {
    print $"✅ DR VERIFY PASSED — all ($targets | length) database\(s) restore and are intact."
  } else {
    print -e $"❌ DR VERIFY FAILED — bad backups: ($failed | str join ', '). Investigate NOW."
    exit 1
  }
}

# Real recovery: restore ONE database to a local sqld data dir (inspect/reload).
# --utc-time gives point-in-time recovery.
def "main restore" [
  namespace: string = "default"     # which database to restore
  --out: string = "turso-restore"
  --generation: string = ""
  --utc-time: string = ""
] {
  hdr $"DR restore — ($namespace)"
  mkdir $out
  let abs = ($out | path expand)
  # restore targets the backup via `-n` and needs `-d` to name the output dir.
  mut args = [-n (nsref $namespace) -d $namespace restore]
  if ($generation | is-not-empty) { $args = ($args | append [-g $generation]) }
  if ($utc_time  | is-not-empty) { $args = ($args | append [-u $utc_time]) }
  let r = (bcli $args --extra-run [-v $"($abs):/out" -w /out])
  if ($r.stdout | str trim | is-not-empty) { print $r.stdout }
  if ($r.stderr | str trim | is-not-empty) { print -e $r.stderr }
  if $r.exit_code != 0 { print -e "❌ restore failed"; exit 1 }
  let dbfile = $"($abs)/($namespace)/dbs/(db):($namespace)/data"
  print $"✅ restored to ($dbfile)"
  print $"   inspect: sqlite3 '($dbfile)' 'PRAGMA integrity_check; .tables'"
}
