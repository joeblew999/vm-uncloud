#!/usr/bin/env nu
# Interactive SQL shell against the turso/libSQL server via the OFFICIAL `turso`
# CLI (`turso db shell`) — the standard client, instead of hand-rolled curl. We
# self-host the SERVER (libsql-server, the turso recipe); this is the CLIENT side.
#
#   mise run turso:shell                          # local `recipe:local turso`
#   mise run turso:shell -- "select 1"            # one-shot query, then exit
#   TURSO_URL=https://db.example.com TURSO_TOKEN=… mise run turso:shell   # deployed
#
# The server is selected by TURSO_URL (default the local server). When auth is on
# (the cluster deploy), pass the client JWT in TURSO_TOKEN (from `turso:token`);
# libSQL takes it as an `authToken` query param on the URL. To target a named
# database (namespace), point TURSO_URL at its subdomain: https://<name>.db.<domain>.
def main [...sql: string] {
  let url = ($env.TURSO_URL?   | default "http://localhost:8080")
  let tok = ($env.TURSO_TOKEN? | default "")
  let target = (if ($tok | is-empty) { $url } else {
    let sep = (if ($url | str contains "?") { "&" } else { "?" })
    $"($url)($sep)authToken=($tok)"
  })
  if ($sql | is-empty) {
    print -e $"turso shell → ($url)   \(auth: (if ($tok | is-empty) { 'off' } else { 'on' })). Ctrl-D to exit."
    ^turso db shell $target
  } else {
    ^turso db shell $target ($sql | str join ' ')
  }
}
