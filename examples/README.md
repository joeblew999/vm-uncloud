# Examples — uncloud-recipes

Ready-made services from recipe repos. We **reference** them rather than copying: `mise run recipe <name>` shallow-clones each source in [`../recipes.toml`](../recipes.toml) into `.src/<source>/` (gitignored), finds `<name>/compose.yaml`, and deploys it. Default source is the upstream [psviderski/uncloud-recipes](https://github.com/psviderski/uncloud-recipes); add your own repos to `recipes.toml`.

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

> ✅ **Verified end-to-end** on a real `cpx22`/`fsn1` box against `amplifycms.net`: `mise run up` → `recipe wordpress-mariadb` produced `https://wordpress.amplifycms.net` serving the WordPress installer over HTTP/2 with a valid Let's Encrypt cert (~80s to first cert), then `mise run down` removed the server, the A record, and the local context.

## How recipes are run (and why this way)

Recipes ship as a **folder** (compose + `.env` + config files like `nats-server.conf`), so a single-file remote deploy won't work — Uncloud resolves those relative paths from the compose file's location. Cloning the folder into `.src/` and running `uc deploy -f .src/<source>/<name>/compose.yaml` keeps upstream pristine and lets Uncloud find everything it needs. Add per-recipe env wiring in [`../scripts/recipe.nu`](../scripts/recipe.nu) as you adopt more, and new recipe repos in [`../recipes.toml`](../recipes.toml).
