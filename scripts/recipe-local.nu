#!/usr/bin/env nu
# Run a recipe LOCALLY via plain `docker compose`, using the SAME committed
# recipes/<name>/compose.yaml as the remote `mise run recipe` path. This keeps
# local and remote DRY: ONE service definition (compose.yaml) and ONE config
# generator (prepare.nu) drive both. The only local-specific bits live in an
# optional sibling recipes/<name>/compose.local.yaml overlay (publish a port,
# disable the reverse-proxy assumptions, localhost hostnames).
#
#   mise run recipe:local rauthy          # up   → http://localhost:<port>
#   mise run recipe:local rauthy --down   # down + remove volumes (reset state)
#
# vs the remote path:
#   mise run recipe rauthy                # uncloud deploy onto the cluster
#
# Secrets come from the recipe's prepare.nu in THROWAWAY mode (VMU_SECRET_DRY=1):
# local data is ephemeral dev state, never your persisted cluster secrets.
# Requires a local Docker daemon (OrbStack / Docker Desktop / Colima).

def main [recipe?: string, --down] {
  if ($recipe | is-empty) {
    print -e "usage: mise run recipe:local <name> [--down]"
    print -e "  runs recipes/<name>/compose.yaml locally via docker compose"
    exit 1
  }
  let base = $"recipes/($recipe)/compose.yaml"
  if not ($base | path exists) {
    print -e $"no local recipe at ($base)"
    exit 1
  }

  # Base + optional local overlay. Both are passed to docker compose so the
  # overlay's values win where they overlap.
  let overlay = $"recipes/($recipe)/compose.local.yaml"
  let has_overlay = ($overlay | path exists)
  let files = (if $has_overlay { [-f $base -f $overlay] } else { [-f $base] })
  let project = $"vmu-($recipe)"

  if $down {
    print $"==> docker compose -p ($project) down -v"
    with-env { DOMAIN: "localhost" } { ^docker compose -p $project ...$files down -v }
    return
  }

  # Same prepare.nu the remote path runs — DOMAIN=localhost + throwaway secrets.
  # (Base compose interpolates ${DOMAIN}; the overlay overrides the user-facing
  # values, but DOMAIN must still resolve for the base to parse.)
  let prep = $"recipes/($recipe)/prepare.nu"
  mut envs = { DOMAIN: "localhost" }
  if ($prep | path exists) {
    let r = (with-env { DOMAIN: "localhost", VMU_SECRET_DRY: "1" } { ^nu $prep } | complete)
    if (($r.stderr | str trim) != "") { print ($r.stderr | str trim) }
    if $r.exit_code != 0 { exit 1 }
    $envs = ($envs | merge ($r.stdout | from json))
  }

  let overlay_note = (if $has_overlay { $" + ($overlay)" } else { "" })
  print $"==> docker compose -p ($project) up -d   [($base)($overlay_note)]"
  with-env $envs { ^docker compose -p $project ...$files up -d }
  print ""
  print $"local '($recipe)' up. logs: docker compose -p ($project) logs -f"
}
