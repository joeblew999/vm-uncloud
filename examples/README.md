# Examples

`mise run recipe <name>` deploys a service by name, checking the **committed examples here first**, then the **upstream catalog** in [`../recipes.toml`](../recipes.toml) (cloned into `.src/` on demand). Local examples are visible, editable, and need no network at deploy time; the upstream catalog covers the long tail.

```bash
mise run recipe            # list everything (examples + upstream)
mise run recipe wordpress  # deploy this repo's WordPress example
```

## Local examples (this repo)

| Example | What | Notes |
|---------|------|-------|
| [`wordpress/`](wordpress/) | WordPress + MariaDB, HTTPS on your domain | Hostname auto-derives to `wordpress.<your-domain>`; DB creds generated; wildcard cert covers it. |

## Upstream catalog ([uncloud-recipes](https://github.com/psviderski/uncloud-recipes))

`nats`, `postgres`, `wordpress-mariadb`, `uncloud-web-ui`, and more — deploy with `mise run recipe <name>`.

## WordPress demo

```bash
mise run up                 # cluster + *.​<domain> wildcard DNS + cert
mise run recipe wordpress   # -> https://wordpress.<your-domain>
```

`recipe wordpress` deploys [`wordpress/compose.yaml`](wordpress/compose.yaml): it reads the cluster's domain from tofu state, publishes WordPress at `wordpress.<that-domain>` (override with `WP_DOMAIN=...`), injects generated `DB_*` credentials, and Uncloud's Caddy serves it with the existing wildcard cert — no per-host setup, no cert wait.

## How it works

Recipes ship as a folder (compose + any `.env`/config files). Uncloud resolves those relative paths from the compose file's location, so `recipe` runs `uc deploy -f <dir>/compose.yaml` from the right place. Per-recipe env wiring lives in [`../scripts/recipe.nu`](../scripts/recipe.nu); new upstream repos go in [`../recipes.toml`](../recipes.toml).
