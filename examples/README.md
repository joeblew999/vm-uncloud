# Examples

Committed, ready-to-deploy recipes. `mise run recipe <name>` resolves a name **here first**, then the upstream catalog in [`../recipes.toml`](../recipes.toml) (cloned into `.src/` on demand).

```bash
mise run recipe            # list everything (local + upstream)
mise run recipe wordpress  # deploy a local example
```

## Local examples

| Example | What |
|---------|------|
| [`wordpress/`](wordpress/) | WordPress + MariaDB on `wordpress.<your-domain>`. Hostname is derived from the cluster domain (override with `WP_DOMAIN=...`), DB credentials are generated, and the wildcard cert covers it. |

## Upstream catalog

[uncloud-recipes](https://github.com/psviderski/uncloud-recipes) — `nats`, `postgres`, `wordpress-mariadb`, `uncloud-web-ui`, and more. Add sources in [`../recipes.toml`](../recipes.toml).

## How a recipe runs

A recipe is a folder (`compose.yaml` plus any `.env`/config files). `recipe` runs `uc deploy -f <dir>/compose.yaml` from the recipe's own directory so Uncloud resolves its relative files. Per-recipe env wiring — e.g. WordPress's hostname and DB credentials — lives in [`../scripts/recipe.nu`](../scripts/recipe.nu).
