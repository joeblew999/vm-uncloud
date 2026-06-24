#!/usr/bin/env nu
# JWT auth for the turso/libSQL server — using libSQL's NATIVE Ed25519/JWT auth
# (SQLD_AUTH_JWT_KEY), not anything hand-rolled. Verified: a minimal EdDSA token
# (claims {"a":"rw"}) signed by the private key is accepted; no/!bad token → 401.
#
#   mise run turso:token    # print the client auth token (for other projects)
#
# Keys are generated ONCE in an alpine+openssl container (macOS LibreSSL has no
# Ed25519) and persisted in the keychain via fnox (stable across redeploys —
# rotating would invalidate every client's token). Stored items:
#   VMU_TURSO_JWT_PRIV   base64(priv.pem)        — to mint more/scoped tokens
#   VMU_TURSO_JWT_PUB    base64url raw pubkey     — SQLD_AUTH_JWT_KEY (env-safe)
#   VMU_TURSO_JWT_TOKEN  the full-access client token (Bearer)
const CFG = "fnox.secrets.toml"

def fget [name: string] {
  let r = (do { ^fnox get -c $CFG $name } | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}
def fset [name: string, val: string] { $val | ^fnox set -c $CFG -p keychain $name | ignore }

# Generate keypair + mint a full-access token, all inside one container.
# Emits three KEY=VALUE lines on stdout.
const GEN = "
apk add -q openssl >/dev/null 2>&1
openssl genpkey -algorithm ed25519 -out /tmp/priv.pem 2>/dev/null
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
PUB=$(openssl pkey -in /tmp/priv.pem -pubout -outform DER | tail -c 32 | b64url)
H=$(printf '%s' '{\"alg\":\"EdDSA\",\"typ\":\"JWT\"}' | b64url)
P=$(printf '%s' '{\"a\":\"rw\"}' | b64url)
printf '%s' \"$H.$P\" > /tmp/si
SIG=$(openssl pkeyutl -sign -inkey /tmp/priv.pem -rawin -in /tmp/si | b64url)
echo \"PRIV=$(openssl base64 -A -in /tmp/priv.pem)\"
echo \"PUB=$PUB\"
echo \"TOKEN=$H.$P.$SIG\"
"

# Get-or-create the keypair + token. Returns { pub, token }.
export def ensure-keys [] {
  let pub = (fget "VMU_TURSO_JWT_PUB")
  let tok = (fget "VMU_TURSO_JWT_TOKEN")
  if ($pub | is-not-empty) and ($tok | is-not-empty) { return { pub: $pub, token: $tok } }
  print -e "turso: generating Ed25519 JWT keypair (one-time, persisted to keychain)…"
  let r = (^docker run --rm --entrypoint sh alpine:latest -c $GEN | complete)
  if $r.exit_code != 0 { print -e $"key generation failed: ($r.stderr)"; exit 1 }
  let kv = ($r.stdout | lines | parse "{k}={v}" | reduce -f {} {|it, acc| $acc | upsert $it.k $it.v })
  fset "VMU_TURSO_JWT_PRIV"  $kv.PRIV
  fset "VMU_TURSO_JWT_PUB"   $kv.PUB
  fset "VMU_TURSO_JWT_TOKEN" $kv.TOKEN
  { pub: $kv.PUB, token: $kv.TOKEN }
}

def main [] { main token }
def "main pubkey" [] { print (ensure-keys | get pub) }
def "main token" [] {
  let t = (ensure-keys | get token)
  print -e "Client auth token (use as the libSQL `authToken`). Keep it secret."
  print $t
}
