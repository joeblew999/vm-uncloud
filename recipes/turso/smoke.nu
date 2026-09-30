#!/usr/bin/env nu
# End-to-end smoke test for the Turso/libSQL recipe — "smoke is code", the same
# philosophy dr.nu applies to recovery. A recipe that "works" is a rumour until a
# runnable check proves it. This drives a LIVE sqld through the exact contract a
# consuming project relies on and exits non-zero if any step regresses, so it can
# gate CI or a scheduled check.
#
#   mise run turso:smoke              # against a local `recipe:local turso`
#   TURSO_URL=… TURSO_ADMIN_URL=… TURSO_TOKEN=… mise run turso:smoke   # any server
#
# What it proves (all via the public libSQL Hrana-over-HTTP API):
#   1. round-trip SQL on the `default` database (create/insert/select)
#   2. create an isolated namespace via the admin API (the multi-DB path)
#   3. round-trip SQL on that namespace, addressed by Host header
#   4. ISOLATION — the `default` database cannot see the namespace's table
#
# Local defaults match compose.local.yaml (HTTP :8080, admin :9090, no auth). On
# an authed server pass TURSO_TOKEN (from `mise run turso:token`).

def base []  { $env.TURSO_URL?       | default "http://localhost:8080" }
def admin [] { $env.TURSO_ADMIN_URL? | default "http://localhost:9090" }
def tok []   { $env.TURSO_TOKEN?     | default "" }

def die [msg: string] { print -e $"❌ SMOKE FAILED — ($msg)"; exit 1 }

# Run SQL statements against ONE database (selected by the Host header — the first
# label is the namespace; a bare host targets `default`) through the libSQL
# pipeline endpoint. Returns the parsed `results` list, or dies on a transport /
# statement error so a failure never passes silently.
def pipeline [host: string, sqls: list<string>] {
  let reqs = (($sqls | each {|s| {type: "execute", stmt: {sql: $s}}}) | append {type: "close"})
  mut headers = {Host: $host}
  if (tok | is-not-empty) { $headers = ($headers | merge {Authorization: $"Bearer (tok)"}) }
  let r = (try {
    http post -t application/json -H $headers --allow-errors -f $"(base)/v2/pipeline" {requests: $reqs}
  } catch {|e| die $"cannot reach sqld at (base) — is it up? \(mise run recipe:local turso). ($e.msg)" })
  if ($r.status? | default 200) >= 400 { die $"HTTP ($r.status) from (base) — ($r.body?)" }
  let results = ($r.body?.results? | default $r.results?)
  if ($results | is-empty) { die $"no results from (base): ($r)" }
  # Any statement-level error surfaces as a result of type "error".
  for res in $results {
    if ($res.type? == "error") { die $"SQL error: ($res.error?.message?)" }
  }
  $results
}

# The single value returned by the last `select` in a pipeline (first row/col).
def scalar [results: list] {
  $results | where ($it.type? == "ok" and ($it.response?.result?.rows? | is-not-empty))
    | last | get response.result.rows.0.0.value
}

def main [] {
  let ns = "smoke"
  print -e $"── turso smoke ─ url=(base) admin=(admin) auth=(if (tok | is-empty) { 'off' } else { 'on' })"

  # 1. default database round-trip.
  pipeline "localhost" [
    "create table if not exists smoke_default(id integer primary key, body text)"
    "delete from smoke_default"
    "insert into smoke_default(body) values ('hello-default')"
  ]
  let got = (pipeline "localhost" ["select body from smoke_default"] | scalar $in)
  if $got != "hello-default" { die $"default round-trip: expected 'hello-default', got '($got)'" }
  print "  ✅ default database round-trips (create/insert/select)"

  # 2. create an isolated namespace via the admin API. Idempotent: ignore a
  #    409/already-exists so re-runs are clean.
  http delete --allow-errors $"(admin)/v1/namespaces/($ns)" | ignore
  let create = (try {
    http post -t application/json -H {Host: (base | url parse | get host)} --allow-errors -f $"(admin)/v1/namespaces/($ns)/create" {}
  } catch {|e| die $"admin API unreachable at (admin) — locally, is 9090 published? \(compose.local.yaml). ($e.msg)" })
  print $"  ✅ namespace '($ns)' created via admin API"

  # 3. round-trip on the namespace, addressed by Host header.
  pipeline $"($ns).db.localhost" [
    "create table isolated(x integer)"
    "insert into isolated values (42)"
  ]
  let nsval = (pipeline $"($ns).db.localhost" ["select x from isolated"] | scalar $in)
  if $nsval != "42" { die $"namespace round-trip: expected 42, got '($nsval)'" }
  print $"  ✅ namespace '($ns)' round-trips via Host routing"

  # 4. ISOLATION — the default database must NOT see the namespace's table.
  let leak = (pipeline "localhost" ["select count(*) from sqlite_master where name='isolated'"] | scalar $in)
  if $leak != "0" { die $"isolation breach: 'default' can see namespace table 'isolated' \(count=($leak))" }
  print "  ✅ isolation holds — default cannot see the namespace's table"

  # cleanup (best-effort; leaves default's smoke table, harmless).
  http delete --allow-errors $"(admin)/v1/namespaces/($ns)" | ignore
  print "✅ SMOKE PASSED — sqld serves the full consumer contract (round-trip + multi-DB + isolation)."
}
