# vm-uncloud

[Uncloud](https://github.com/psviderski/uncloud) cluster on a Hetzner VPS, on your own Cloudflare domain. Create it, deploy apps, tear it down. The only tool you install is [`mise`](https://mise.jdx.dev).

```bash
mise install      # opentofu, hcloud, nushell, fnox
mise run setup    # the uncloud CLI (uc)
mise run up       # server + wildcard DNS + cluster
mise run deploy   # deploy compose.yaml
mise run down     # destroy everything
```

## Setup

Need: a Cloudflare zone + token (`Zone:DNS:Edit`), a Hetzner project + SSH key.

```bash
cp tofu/terraform.tfvars.example tofu/terraform.tfvars   # set domain, cloudflare_zone_id, ssh_key_name
mise run secrets:set                                     # tokens -> keychain
mise run up
```

Run `up`/`down` from a real terminal (`uc` uses a TTY). Secrets stay in the keychain via `fnox`, never on disk. TLS is one `*.<domain>` wildcard cert via Cloudflare DNS-01 — any subdomain just works.

## Config — `tofu/terraform.tfvars`

| Variable | Default | |
|---|---|---|
| `domain` | — | your apex, e.g. `example.com` |
| `cloudflare_zone_id` | — | Cloudflare dashboard sidebar |
| `ssh_key_name` | — | an SSH key in your Hetzner project |
| `node_count` | `1` | `3` for a mesh |
| `server_type` | `cpx22` | `cax11` = ARM |
| `location` | `fsn1` | `nbg1` `hel1` `ash` `hil` `sin` |
| `dns_apex` | `false` | also point the apex at the box |

## Deploy

Use `${DOMAIN}` in compose — never hardcode the host; `mise run deploy` injects it.

```yaml
services:
  api:
    build: .
    x-ports: ["api.${DOMAIN}:8080/https"]
```

```bash
mise run deploy        # build + push changed layers + roll out
mise watch deploy      # re-deploy on save
mise run push [image]  # push only — built-in registry, no docker pull
```

Building needs local Docker (e.g. OrbStack on a Mac); the push is `uc`'s own. Build arch must match the server: `cpx22` is x86, so build `linux/amd64` (set `platform: linux/amd64` on the service) — or use `cax11` ARM nodes to match an Apple-silicon Mac.

## Recipes

Ready-to-run services in [`recipes/`](recipes/) (local first, then [`recipes.toml`](recipes.toml) upstream):

```bash
mise run recipe                  # list
mise run recipe wordpress        # WordPress + MariaDB
mise run recipe imaginary        # libvips image API (h2non/imaginary)
mise run recipe moltis           # self-hosted AI agent server
mise run recipe wordpress-galera # EXPERIMENTAL — multi-master (needs node_count >= 3)
```

A recipe is a folder: `compose.yaml` + optional `prepare.nu` (generates and persists its own secrets). Adding one touches no shared code.

## State

```bash
mise run status        # machines, services, history
mise run state:remote  # move tofu state to Cloudflare R2 (durable, lockable)
```

`state/log.jsonl` is the up/deploy/down ledger (in git). `tofu` uses `HCLOUD_TOKEN` — verify infra with `fnox exec -- hcloud server list`, not bare `hcloud`.

## External services

Front non-container hosts (BMC, HomeAssistant, NAS) through Caddy:

```bash
cp caddy/external.caddyfile.example caddy/external.caddyfile   # edit it
mise run caddy:external
```

## Checks

`mise run ci` (and every push, via [`.github/workflows/check.yml`](.github/workflows/check.yml)) — tofu fmt/validate, parse scripts, run each `prepare.nu`, parse composes.

## Troubleshooting

- **No cert** — `docker logs $(docker ps -qf name=caddy) | grep -i acme`. Caddy must be `caddybuilds/caddy-cloudflare` with `CLOUDFLARE_API_TOKEN` set.
- **`could not open TTY`** — run from a real terminal, not CI.
- **`context not found`** — must match `$UNCLOUD_CONTEXT` (`hetzner`); `mise run up` sets it.

## vm-* family

[vm-uncloud](.) — Linux apps/containers · [vm-servers](https://github.com/joeblew999/vm-servers) — Windows VMs · [vm-software](https://github.com/joeblew999/vm-software) — Windows installers.
