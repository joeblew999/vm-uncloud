#!/usr/bin/env nu
# Durability for turso-sync. The NEW Turso engine has no bottomless (that's the
# `turso`/sqld recipe's job). Its sync server keeps a growing WAL with checkpoint
# disabled, so the durable primitive is an ONLINE CONSISTENT SNAPSHOT:
#
#   VACUUM INTO '<file>'   over /v2/pipeline  →  a clean single-file SQLite copy
#
# taken while the server runs, then shipped to S3-compatible storage (R2). Restore
# = pull the snapshot back and make it the server's DB file. This is the same
# "R2 is the source of truth, the box is disposable" story as the sqld recipe,
# minus streaming — a snapshot cadence bounds the loss window instead.
#
#   mise run turso-sync:backup           # snapshot -> R2 (or MinIO for tests)
#   mise run turso-sync:backup:verify    # snapshot -> restore -> integrity check
#   mise run turso-sync:restore          # pull latest snapshot to a local file
#
# S3 target: defaults to R2 (creds derived from CLOUDFLARE_API_TOKEN like the tofu
# backend + sqld recipe). Override for tests/self-host by setting TURSO_SYNC_ENDPOINT
# + AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY (e.g. a local MinIO).
use ../../scripts/r2.nu *

def project   [] { $env.TURSO_SYNC_PROJECT?   | default "vmu-turso-sync" }
def bucket    [] { $env.TURSO_SYNC_BUCKET?    | default "vm-uncloud-turso-sync" }
def url       [] { $env.TURSO_SYNC_URL?       | default "http://localhost:8080" }
# The running container (compose names it <project>-<service>-<index>). Override
# TURSO_SYNC_CONTAINER for the cluster (uncloud) where naming differs.
def container [] { $env.TURSO_SYNC_CONTAINER? | default $"(project)-turso-sync-1" }

# Resolve the S3 endpoint + creds: explicit env (MinIO/self-host) wins, else R2.
def s3-config [] {
  let ep = ($env.TURSO_SYNC_ENDPOINT? | default "")
  if ($ep | is-not-empty) {
    { endpoint: $ep,
      akid: ($env.AWS_ACCESS_KEY_ID? | default ""),
      secret: ($env.AWS_SECRET_ACCESS_KEY? | default ""),
      region: ($env.AWS_DEFAULT_REGION? | default "auto") }
  } else {
    let c = (r2-derive)
    { endpoint: (r2-endpoint), akid: $c.AWS_ACCESS_KEY_ID, secret: $c.AWS_SECRET_ACCESS_KEY, region: $c.AWS_DEFAULT_REGION }
  }
}

# Run the aws CLI (a repo tool) against the chosen S3 endpoint, with the creds in
# the process env. Returns {stdout,stderr,exit_code}.
def aws-run [args: list<string>] {
  let s = (s3-config)
  with-env { AWS_ACCESS_KEY_ID: $s.akid, AWS_SECRET_ACCESS_KEY: $s.secret, AWS_DEFAULT_REGION: $s.region } {
    (^aws --endpoint-url $s.endpoint s3 ...$args | complete)
  }
}

# Trigger an online VACUUM INTO on the server, producing a consistent snapshot at
# the given in-container path.
def snapshot-on-server [container_path: string] {
  let body = { requests: [ { type: "execute", stmt: { sql: $"vacuum into '($container_path)'" } } ] }
  let r = (http post -t application/json --allow-errors -f $"(url)/v2/pipeline" $body)
  if (($r.status? | default 200) >= 400) { error make {msg: $"VACUUM INTO failed: HTTP ($r.status) ($r.body?)"} }
}

def hdr [m: string] { print -e $"── ($m) ─ bucket=(bucket) endpoint=((s3-config).endpoint)" }

def main [] { print -e "turso-sync backup — snapshot | restore | verify" }

# Snapshot the live server and upload to S3 (R2/MinIO). Local recipe: extract the
# snapshot via `docker compose cp` from the container volume.
def "main snapshot" [--key: string = "latest.db"] {
  hdr "snapshot"
  let cpath = "/data/snapshot.db"
  snapshot-on-server $cpath
  let tmp = (mktemp -t turso-sync-snap.XXXXXX.db)
  # Extract the consistent file from the running container.
  (^docker cp $"(container):($cpath)" $tmp | complete | get exit_code)
  let up = (aws-run [cp $tmp $"s3://(bucket)/($key)"])
  rm -f $tmp
  if $up.exit_code != 0 { print -e $"❌ upload failed: ($up.stderr | str trim)"; exit 1 }
  print $"✅ snapshot uploaded to s3://(bucket)/($key)"
}

# Restore the latest snapshot to a local file (recovery / inspection).
def "main restore" [--key: string = "latest.db", --out: string = "turso-sync-restore.db"] {
  hdr $"restore -> ($out)"
  let dl = (aws-run [cp $"s3://(bucket)/($key)" $out])
  if $dl.exit_code != 0 { print -e $"❌ download failed: ($dl.stderr | str trim)"; exit 1 }
  print $"✅ restored snapshot to ($out) — inspect: tursodb '($out)' 'select ...'"
}

# THE DRILL: snapshot -> restore to a throwaway file -> integrity check. Exits
# non-zero if the snapshot is unrecoverable, so it can gate CI / a schedule.
def "main verify" [--key: string = "verify.db"] {
  hdr "backup VERIFY (drill)"
  main snapshot --key $key
  let out = (mktemp -t turso-sync-verify.XXXXXX.db)
  let dl = (aws-run [cp $"s3://(bucket)/($key)" $out])
  if $dl.exit_code != 0 { print -e "❌ VERIFY FAILED — cannot download snapshot"; exit 1 }
  # integrity check via tursodb from the running container image (no host install):
  # copy the downloaded snapshot IN, then run pragma integrity_check on it.
  (^docker cp $out $"(container):/tmp/verify.db" | complete)
  let chk = (^docker exec (container) tursodb /tmp/verify.db "pragma integrity_check" | complete)
  rm -f $out
  if ($chk.stdout | str contains "ok") {
    print "✅ BACKUP VERIFY PASSED — snapshot restores and passes integrity_check."
  } else {
    print -e $"❌ BACKUP VERIFY FAILED — integrity check did not return ok: ($chk.stdout)"
    exit 1
  }
}
