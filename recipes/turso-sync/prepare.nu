#!/usr/bin/env nu
# Config for the turso-sync recipe. recipe.nu runs this with DOMAIN in the env and
# merges the JSON it prints on stdout into the deploy env; stderr is notes.
#
# The NEW Turso sync server (tursodb --sync-server) has NO native auth, TLS, or
# off-box backup (unlike the `turso`/sqld recipe — see compose.yaml). So there are
# no secrets to derive here yet; this just surfaces the BETA/no-backup caveats and
# passes DOMAIN through for the compose ${DOMAIN} interpolation. When durability
# (litestream -> R2) and an auth proxy land, their config gets wired in here.
def main [] {
  print -e "turso-sync: BETA new-engine sync server."
  print -e "  ⚠ no native auth / TLS / off-box backup yet — do NOT expose publicly unguarded,"
  print -e "    and note the data volume is currently the only copy (durability TODO)."
  { DOMAIN: ($env.DOMAIN? | default "localhost") } | to json
}
