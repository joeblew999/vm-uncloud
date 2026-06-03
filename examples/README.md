# Examples — uncloud-recipes

Ready-made services from recipe repos. We **reference** them rather than copying: `mise run recipe <name>` shallow-clones each source in [`../recipes.toml`](../recipes.toml) into `.src/<source>/` (gitignored), finds `<name>/compose.yaml`, and deploys it. Default source is the upstream [psviderski/uncloud-recipes](https://github.com/psviderski/uncloud-recipes); add your own repos to `recipes.toml`.

```bash
mise run up                              # cluster must exist first
mise run recipe <name>
```

| Recipe | What it is | Notes |
|--------|-----------|-------|
| [`wordpress-mariadb`](https://github.com/psviderski/uncloud-recipes/tree/main/wordpress-mariadb) | WordPress + MariaDB, HTTPS on your domain | **Best domain demo.** Set `WP_DOMAIN` to any subdomain — the wildcard record + cert cover it. |
| [`nats`](https://github.com/psviderski/uncloud-recipes/tree/main/nats) | NATS cluster with JetStream | Global mode (one per machine), host-port only — no public URL. |
| [`postgres`](https://github.com/psviderski/uncloud-recipes/tree/main/postgres) | PostgreSQL 18 | Host-port only; bind to localhost. |
| [`uncloud-web-ui`](https://github.com/psviderski/uncloud-recipes/tree/main/uncloud-web-ui) | Read-only cluster dashboard (Bun, PoC) | Needs a local build; mounts the uncloud socket. |

## Deploy WordPress on your domain

```bash
# 1. bring up the cluster (creates the *.<domain> wildcard record + cert)
mise run up

# 2. deploy the recipe on any subdomain — no per-host setup needed
WP_DOMAIN=wordpress.amplifycms.net mise run recipe wordpress-mariadb
```

`recipe wordpress-mariadb` generates random DB credentials and injects `WP_DOMAIN` + `DB_*` as environment for the deploy. The wildcard cert already covers `wordpress.amplifycms.net`, so it's served over HTTPS immediately — no per-host cert wait.

> The context-naming fix, recipe deploy, full `up`/`deploy`/`down` ledger lifecycle, and clean teardown were verified end-to-end on a real `cpx22`/`fsn1` box against `amplifycms.net`. (An earlier per-host **HTTP-01** run also served WordPress over a valid cert; the move to wildcard **DNS-01** removes the cert-issuance flakiness seen on rapid re-runs.)

## How recipes are run (and why this way)

Recipes ship as a **folder** (compose + `.env` + config files like `nats-server.conf`), so a single-file remote deploy won't work — Uncloud resolves those relative paths from the compose file's location. Cloning the folder into `.src/` and running `uc deploy -f .src/<source>/<name>/compose.yaml` keeps upstream pristine and lets Uncloud find everything it needs. Add per-recipe env wiring in [`../scripts/recipe.nu`](../scripts/recipe.nu) as you adopt more, and new recipe repos in [`../recipes.toml`](../recipes.toml).
