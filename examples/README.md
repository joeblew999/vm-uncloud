# Examples — uncloud-recipes

Ready-made services from the upstream [psviderski/uncloud-recipes](https://github.com/psviderski/uncloud-recipes) collection. We **reference** that repo rather than copying it: `mise run recipe <name>` shallow-clones it into `.src/uncloud-recipes/` (gitignored) and deploys the chosen recipe to your cluster.

```bash
mise run up                              # cluster must exist first
mise run recipe <name>
```

| Recipe | What it is | Notes |
|--------|-----------|-------|
| [`wordpress-mariadb`](https://github.com/psviderski/uncloud-recipes/tree/main/wordpress-mariadb) | WordPress + MariaDB, HTTPS on your domain | **Best domain demo.** Set `WP_DOMAIN` to a hostname you created in `app_hostnames`. |
| [`nats`](https://github.com/psviderski/uncloud-recipes/tree/main/nats) | NATS cluster with JetStream | Global mode (one per machine), host-port only — no public URL. |
| [`postgres`](https://github.com/psviderski/uncloud-recipes/tree/main/postgres) | PostgreSQL 18 | Host-port only; bind to localhost. |
| [`uncloud-web-ui`](https://github.com/psviderski/uncloud-recipes/tree/main/uncloud-web-ui) | Read-only cluster dashboard (Bun, PoC) | Needs a local build; mounts the uncloud socket. |

## Deploy WordPress on your domain

```bash
# 1. add the hostname so DNS + cert work
#    in tofu/terraform.tfvars: app_hostnames = ["wordpress"]
mise run up

# 2. deploy the recipe pointed at that hostname
WP_DOMAIN=wordpress.amplifycms.net mise run recipe wordpress-mariadb
```

`recipe wordpress-mariadb` generates random DB credentials and injects `WP_DOMAIN` + `DB_*` as environment for the deploy. Uncloud's Caddy obtains a Let's Encrypt cert for the hostname automatically; browse to `https://wordpress.amplifycms.net` once the cert is issued (~30–60s).

## How recipes are run (and why this way)

Recipes ship as a **folder** (compose + `.env` + config files like `nats-server.conf`), so a single-file remote deploy won't work — Uncloud resolves those relative paths from the compose file's location. Cloning the folder into `.src/` and running `uc deploy -f .src/uncloud-recipes/<name>/compose.yaml` keeps upstream pristine and lets Uncloud find everything it needs. Add per-recipe env wiring in [`../scripts/recipe.nu`](../scripts/recipe.nu) as you adopt more.
