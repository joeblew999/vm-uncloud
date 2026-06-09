#!/usr/bin/env nu
# registry.nu — publish "what's live" into OrangeVault so other systems can
# discover it. When vm-uncloud deploys a recipe/node, it records the public URL as
# a Bitwarden login item named `vmu/<context>/<service>` with the URL in the `uri`
# field — so any repo whose fnox has the orangevault provider resolves it with:
#   { provider = "orangevault", value = "vmu/<context>/<service>/uri" }
# OrangeVault becomes the registry of live systems; vm-uncloud + the stuff it runs
# is then self-describing and leverageable. (Russian doll, by design.)
#
# Writes go through the `bw` CLI against the DEDICATED dev/CI account (creds from
# the keychain, ORANGEVAULT_DEV_*; URL from $ORANGEVAULT_DEV_DOMAIN). Everything is
# BEST-EFFORT and self-guarding: with no bw / no creds it no-ops, so it can never
# break a deploy. Auto-publish on deploy is OPT-IN (VMU_REGISTRY=1) — until then
# use `mise run registry:publish` / `registry:list` to exercise it live first.
#
# EXPERIMENTAL: the bw item CRUD here is verify-on-first-use against a live vault.

# Read a global keychain item via fnox; "" if unset / fnox absent.
def kc [key: string] {
  if (which fnox | is-empty) { return "" }
  let r = (do { ^fnox get $key } | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

# Ensure bw is pointed at OrangeVault and unlocked; returns BW_SESSION or "" if the
# registry can't be used (best-effort — never throws).
def ensure-unlocked [] {
  if (which bw | is-empty) { return "" }
  let server = ($env.ORANGEVAULT_DEV_DOMAIN? | default "" | str trim)
  let server = (if ($server | is-empty) { kc "ORANGEVAULT_DEV_DOMAIN" } else { $server })
  let cid = (kc "ORANGEVAULT_DEV_BW_CLIENTID")
  let pw  = (kc "ORANGEVAULT_DEV_MASTER_PASSWORD")
  if (($server | is-empty) or ($cid | is-empty) or ($pw | is-empty)) { return "" }
  do { ^bw config server $server } | complete | ignore
  let st = (do { ^bw status } | complete)
  let status = (try { $st.stdout | from json | get status } catch { "unauthenticated" })
  if $status == "unauthenticated" {
    with-env { BW_CLIENTID: $cid, BW_CLIENTSECRET: (kc "ORANGEVAULT_DEV_BW_CLIENTSECRET") } {
      do { ^bw login --apikey } | complete | ignore
    }
  }
  let s = (do { $pw | ^bw unlock --raw } | complete)
  if $s.exit_code == 0 { $s.stdout | str trim } else { "" }
}

def item-name [context: string, service: string] { $"vmu/($context)/($service)" }

# Publish/update a live system's URL. Best-effort; no-op if registry unconfigured.
def "main publish" [--context: string, --service: string, --url: string, --kind: string = "service"] {
  if (($context | is-empty) or ($service | is-empty) or ($url | is-empty)) {
    print -e "registry publish: --context, --service and --url are required"; return
  }
  let sess = (ensure-unlocked)
  if ($sess | is-empty) {
    print -e "registry: OrangeVault not configured (need bw + ORANGEVAULT_DEV_*) — skipping publish"; return
  }
  let name = (item-name $context $service)
  with-env { BW_SESSION: $sess } {
    do { ^bw sync } | complete | ignore
    let existing = (do { ^bw get item $name } | complete)
    let notes = ({ context: $context, service: $service, kind: $kind, url: $url, updated: (date now | format date "%+") } | to json)
    let tmpl = (try { ^bw get template item | from json } catch { {} })
    let item = ($tmpl
      | upsert type 1
      | upsert name $name
      | upsert notes $notes
      | upsert login { username: null, password: null, totp: null, uris: [{ match: null, uri: $url }] })
    let r = (if $existing.exit_code == 0 {
        let id = ($existing.stdout | from json | get id)
        do { $item | to json | ^bw encode | ^bw edit item $id } | complete
      } else {
        do { $item | to json | ^bw encode | ^bw create item } | complete
      })
    if $r.exit_code == 0 { print $"registry: published ($name) -> ($url)" } else { print -e $"registry: publish failed for ($name) \(verify bw item CRUD\)" }
  }
}

# List registered live systems (optionally filtered by context).
def "main list" [--context: string = ""] {
  let sess = (ensure-unlocked)
  if ($sess | is-empty) { print -e "registry: OrangeVault not configured — nothing to list"; return }
  let q = (if ($context | is-empty) { "vmu/" } else { $"vmu/($context)/" })
  with-env { BW_SESSION: $sess } {
    let r = (do { ^bw list items --search $q } | complete)
    if $r.exit_code != 0 { print -e "registry: list failed"; return }
    (try { $r.stdout | from json } catch { [] })
      | where {|it| ($it.name? | default "" | str starts-with $q) }
      | each {|it| { name: $it.name, url: ($it.login?.uris? | default [] | get 0?.uri? | default "") } }
      | table
  }
}

# Remove a registered system (e.g. on teardown).
def "main remove" [--context: string, --service: string] {
  let sess = (ensure-unlocked)
  if ($sess | is-empty) { print -e "registry: OrangeVault not configured — skipping remove"; return }
  let name = (item-name $context $service)
  with-env { BW_SESSION: $sess } {
    let existing = (do { ^bw get item $name } | complete)
    if $existing.exit_code != 0 { print -e $"registry: ($name) not found"; return }
    let id = ($existing.stdout | from json | get id)
    do { ^bw delete item $id } | complete | ignore
    print $"registry: removed ($name)"
  }
}

def main [] {
  print "registry.nu — publish/list/remove live-system URLs in OrangeVault."
  print "  nu scripts/registry.nu publish --context <c> --service <s> --url <u> [--kind <k>]"
  print "  nu scripts/registry.nu list [--context <c>]"
  print "  nu scripts/registry.nu remove --context <c> --service <s>"
}
