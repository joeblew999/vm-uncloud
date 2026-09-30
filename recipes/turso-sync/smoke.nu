#!/usr/bin/env nu
# End-to-end smoke test for the turso-sync recipe — "smoke is code" (same idiom as
# recipes/turso/smoke.nu). Proves a running tursodb sync server serves the open
# sync protocol both offline clients rely on, and exits non-zero on regression so
# it can gate CI / a scheduled check.
#
#   mise run recipe:local turso-sync    # build + run the sync server (:8080)
#   mise run turso-sync:smoke           # → ✅ SMOKE PASSED
#   TURSO_SYNC_URL=… mise run turso-sync:smoke   # against any deployed server
#
# What it proves:
#   1. POST /v2/pipeline — SQL-over-HTTP round-trip (create/insert/select)
#   2. POST /pull-updates — the protobuf page-sync endpoint exists (offline pull)
#
# NB the reference sync server's Hrana dialect accepts only `execute`/`batch`
# requests (no `close`), and this engine is BETA — see the recipe README.
def base [] { $env.TURSO_SYNC_URL? | default "http://localhost:8080" }
def die [msg: string] { print -e $"❌ SMOKE FAILED — ($msg)"; exit 1 }

# Run execute statements through /v2/pipeline; returns the parsed results, dying
# on any transport- or statement-level error.
def pipeline [sqls: list<string>] {
  let reqs = ($sqls | each {|s| {type: "execute", stmt: {sql: $s}}})
  let r = (try {
    http post -t application/json --allow-errors -f $"(base)/v2/pipeline" {requests: $reqs}
  } catch {|e| die $"cannot reach the sync server at (base) — is it up? \(mise run recipe:local turso-sync). ($e.msg)" })
  if ($r.status? | default 200) >= 400 { die $"HTTP ($r.status) from /v2/pipeline — ($r.body?)" }
  let results = ($r.body?.results? | default $r.results?)
  if ($results | is-empty) { die $"no results: ($r)" }
  for res in $results { if ($res.type? == "error") { die $"SQL error: ($res.error?.message?)" } }
  $results
}

def scalar [results: list] {
  $results | where ($it.type? == "ok" and ($it.response?.result?.rows? | is-not-empty))
    | last | get response.result.rows.0.0.value
}

def main [] {
  print -e $"── turso-sync smoke ─ url=(base)"

  # 1. SQL-over-HTTP round-trip.
  pipeline [
    "create table if not exists smoke(id integer primary key, body text)"
    "delete from smoke"
    "insert into smoke(body) values ('sync-works')"
  ]
  let got = (pipeline ["select body from smoke"] | scalar $in)
  if $got != "sync-works" { die $"round-trip: expected 'sync-works', got '($got)'" }
  print "  ✅ /v2/pipeline round-trips (SQL over HTTP)"

  # 2. /pull-updates must exist (offline clients pull page updates from it). A
  #    minimal/garbage protobuf body should NOT 404 — a 404 means no sync engine.
  let pu = (try {
    http post --content-type application/protobuf --allow-errors -f $"(base)/pull-updates" (0x[00])
  } catch {|e| die $"cannot reach /pull-updates at (base): ($e.msg)" })
  if ($pu.status? | default 200) == 404 { die "/pull-updates returned 404 — this server has no sync engine" }
  print $"  ✅ /pull-updates present \(HTTP ($pu.status? | default 200)) — the page-sync endpoint offline clients pull from"

  print "✅ SMOKE PASSED — tursodb serves the sync protocol (/v2/pipeline + /pull-updates)."
}
