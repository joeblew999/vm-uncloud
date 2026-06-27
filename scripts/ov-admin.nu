#!/usr/bin/env nu
# ov-admin.nu — thin client for orangevault-admin's ConnectRPC AdminService. No
# compiled binary needed: Connect speaks JSON over HTTP, so this just POSTs to
# /orangevault_admin.v1.AdminService/<Method> (see the orangevault-admin repo).
#
# Reads ORANGEVAULT_ADMIN_DOMAIN + ORANGEVAULT_ADMIN_TOKEN (bearer macaroon) from
# fnox — the same keys the orangevault-admin repo uses. Guarded/best-effort.
#
# NOTE: orangevault-admin's auth middleware is WIP ("no auth middleware yet"), so
# this is verify-on-first-use and shouldn't be pointed at a public admin worker
# until that lands.

def kc [key: string] {
  if (which fnox | is-empty) { return "" }
  let r = (do { ^fnox get $key } | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

def admin-base [] {
  let d = ($env.ORANGEVAULT_ADMIN_DOMAIN? | default "" | str trim)
  let d = (if ($d | is-empty) { kc "ORANGEVAULT_ADMIN_DOMAIN" } else { $d })
  ($d | str trim --char '/' --right)
}

# Unary ConnectRPC call → parsed JSON record, or null on any failure.
def call [method: string, body: record] {
  let base = (admin-base)
  if ($base | is-empty) { print -e "ov-admin: ORANGEVAULT_ADMIN_DOMAIN not set (fnox or env)"; return null }
  let token = (kc "ORANGEVAULT_ADMIN_TOKEN")
  let hdrs = (if ($token | is-empty) {
      { "Content-Type": "application/json" }
    } else {
      { "Content-Type": "application/json", "Authorization": $"Bearer ($token)" }
    })
  let url = $"($base)/orangevault_admin.v1.AdminService/($method)"
  try { http post --headers $hdrs $url ($body | to json) } catch {|e| print -e $"ov-admin: ($method) failed — ($e.msg)"; null }
}

def "main healthz" [] {
  let r = (call "Healthz" {})
  if ($r == null) { exit 1 }
  print ($r | to json)
}

def "main list-users" [--page-size: int = 50] {
  let r = (call "ListUsers" { page_size: $page_size })
  if ($r == null) { exit 1 }
  ($r | get users? | default [] | select id? email? name? | table)
}

def "main get-user" [user_id: string] {
  let r = (call "GetUser" { user_id: $user_id })
  if ($r == null) { exit 1 }
  print ($r | to json)
}

def "main list-orgs" [] {
  let r = (call "ListOrganizations" {})
  if ($r == null) { exit 1 }
  ($r | get organizations? | default [] | table)
}

def main [] {
  print "ov-admin.nu — orangevault-admin ConnectRPC client (JSON over HTTP)."
  print "  nu scripts/ov-admin.nu healthz"
  print "  nu scripts/ov-admin.nu list-users [--page-size 50]"
  print "  nu scripts/ov-admin.nu get-user <user_id>"
  print "  nu scripts/ov-admin.nu list-orgs"
  print "needs ORANGEVAULT_ADMIN_DOMAIN (+ ORANGEVAULT_ADMIN_TOKEN for non-healthz) in fnox/env."
}
