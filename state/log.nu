#!/usr/bin/env nu
# Typed ledger of cluster lifecycle events in state/log.jsonl — the durable
# record of "what is (or was) on what servers". Mirrors vm-servers/state.
#
# JSONL: one event per line, each self-contained, auto-timestamped. The live
# truth is `uc machine ls` / `uc ls` + tofu state; this ledger is the history
# that survives teardown. Persist via git: `git add state/log.jsonl && push`.
#
# Called as a subprocess by up.nu / recipe.nu / down.nu:
#   nu state/log.nu up     --cluster hetzner --ips 1.2.3.4 --server-type cpx22 --location fsn1 --fqdns app.example.com
#   nu state/log.nu deploy --cluster hetzner --service wordpress-mariadb --host wordpress.example.com
#   nu state/log.nu down   --cluster hetzner

def now_ts [] { date now | format date "%Y-%m-%dT%H:%M:%S%z" }

def append [rec: record] {
  mkdir state
  let line = ($rec | upsert ts (now_ts) | to json -r)
  $"($line)\n" | save -a state/log.jsonl
}

def "main up" [--cluster: string, --ips: string = "", --server-type: string = "", --location: string = "", --fqdns: string = ""] {
  append { event: up, cluster: $cluster, ips: $ips, server_type: $server_type, location: $location, fqdns: $fqdns }
}

def "main deploy" [--cluster: string, --service: string, --host: string = ""] {
  append { event: deploy, cluster: $cluster, service: $service, host: $host }
}

def "main down" [--cluster: string, --location: string = "", --server-type: string = ""] {
  append { event: down, cluster: $cluster, location: $location, server_type: $server_type }
}

def main [] {
  print "usage: nu state/log.nu (up|deploy|down) --cluster <name> [...]"
}
