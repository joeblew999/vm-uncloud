# Persisted secrets — the best approach until Uncloud ships native secrets.
#
# Generate a value once, store it in the OS keychain via fnox (pointers in the
# gitignored fnox.secrets.toml, the value itself in the keychain), and reuse it on
# every deploy. This keeps generated credentials STABLE across redeploys —
# regenerating a DB password each deploy would lock you out of the persistent
# volume — and keeps secrets off committed files. Falls back to an ephemeral
# value where the keychain isn't available (e.g. CI on Linux).

const CFG = "fnox.secrets.toml"

def ensure-cfg [] {
  if not ($CFG | path exists) {
    "[providers.keychain]\ntype = \"keychain\"\nservice = \"fnox\"\n\n[secrets]\n" | save -f $CFG
  }
}

# Get-or-create a stable secret of the given length.
export def secret [name: string, length: int = 32] {
  # CI / dry checks: don't touch the keychain, just return a throwaway value.
  if (($env.VMU_SECRET_DRY? | default "") == "1") { return (random chars --length $length) }
  ensure-cfg
  let got = (do { ^fnox get -c $CFG $name } | complete)
  if ($got.exit_code == 0) {
    let v = ($got.stdout | str trim)
    if ($v != "") { return $v }
  }
  let val = (random chars --length $length)
  do { $val | ^fnox set -c $CFG -p keychain $name } | complete | ignore
  $val
}

# Get-or-create a stable base64-encoded random key of `bytes` raw bytes.
# `secret` only yields alphanumeric, but some configs need a real base64 key —
# e.g. Rauthy's ENC_KEYS wants a base64-encoded 32-byte value. Same persistence
# guarantee as `secret`: generated once, stable across redeploys (changing an
# encryption key after data is written makes that data undecryptable).
export def secret-b64 [name: string, bytes: int = 32] {
  if (($env.VMU_SECRET_DRY? | default "") == "1") { return (^openssl rand -base64 $bytes | str trim) }
  ensure-cfg
  let got = (do { ^fnox get -c $CFG $name } | complete)
  if ($got.exit_code == 0) {
    let v = ($got.stdout | str trim)
    if ($v != "") { return $v }
  }
  let val = (^openssl rand -base64 $bytes | str trim)
  do { $val | ^fnox set -c $CFG -p keychain $name } | complete | ignore
  $val
}
