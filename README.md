# vm-uncloud

Spin up an [Uncloud](https://github.com/psviderski/uncloud) cluster on a Hetzner VPS, served on your own Cloudflare domain. It creates the server, points your domain at it, installs Uncloud, deploys your apps — and tears it all down just as fast. Built with `mise`, `nushell`, and OpenTofu; secrets from `fnox`/keychain.

```bash
mise install        # fetches opentofu, hcloud, nushell, fnox
mise run setup      # installs the uncloud CLI (uc)
mise run up         # server + wildcard DNS + cluster
mise run deploy     # deploy compose.yaml   (or: mise run recipe wordpress)
mise run down       # destroy everything, cleanly
```

The only tool you install by hand is [`mise`](https://mise.jdx.dev); it fetches the rest.

## The `vm-*` family

| Repo | For |
|------|-----|
| **vm-uncloud** (this) | Host **Linux web apps / containers** — Uncloud on Hetzner + Cloudflare DNS + auto-HTTPS, deployed via Docker Compose. |
| [vm-servers](https://github.com/joeblew999/vm-servers) | Run **Windows in a VM** — Mac control plane, Hetzner/Vultr drivers, R2 snapshots. |
| [vm-software](https://github.com/joeblew999/vm-software) | Catalog of **Windows installers**, git-cloned inside a vm-servers VM. |

This repo is the **platform**. Your apps keep their own `compose.yaml` and `Dockerfile` in their own repos and deploy onto it.

## How it works

Uncloud installs itself onto a fresh Linux box over SSH — you never copy binaries up. The two things its CLI doesn't do — create the box and point your domain at it — are what OpenTofu handles here.

TLS is a single **wildcard certificate** issued via the Cloudflare **DNS-01** challenge (Caddy runs the `caddybuilds/caddy-cloudflare` image). One `*.<domain>` cert, so:

- a single wildcard `A` record covers every subdomain — no per-host DNS;
- the cert is issued once at bring-up and instantly covers any subdomain you publish later;
- no port-80 dependency, no per-host issuance, no Let's Encrypt rate limits.

| Where | What | By |
|-------|------|----|
| Your machine | `uncloud` CLI (`uc`) | `mise run setup` |
| Hetzner box | readiness gate (SSH + cloud-init) | tofu `remote-exec` provisioner — `apply` blocks until ready |
| Hetzner box | Docker, `uncloudd`, WireGuard mesh, cluster | `uc machine init` over SSH |
| Hetzner box | wildcard DNS-01 Caddy ingress | `caddy/compose.yaml` |
| Cloudflare | `*.<domain>` wildcard `A` record | OpenTofu |

WireGuard ships in the kernel. `corrosion` (cluster state) is bundled in `uncloudd`. The image registry (`unregistry`) is built into Uncloud. The Cloudflare token sits on the box for DNS-01 — scope it to `Zone:DNS:Edit`.

## Setup

You provide a **Cloudflare** zone + API token (`Zone:DNS:Edit`) and a **Hetzner** project + SSH key. Then:

```bash
mise install                      # opentofu, hcloud, nushell, fnox
mise run setup                    # uncloud CLI (uc)

cp tofu/terraform.tfvars.example tofu/terraform.tfvars
$EDITOR tofu/terraform.tfvars     # domain, cloudflare_zone_id, ssh_key_name

mise run secrets:set              # store HCLOUD_TOKEN + CLOUDFLARE_API_TOKEN in the keychain
mise run up
```

Secrets live in the macOS keychain (`fnox`) and are injected by `fnox exec`; the OpenTofu providers read `HCLOUD_TOKEN` and `CLOUDFLARE_API_TOKEN` from the environment, never disk. SSH uses `~/.ssh/gedw99_hetzner`. Run `up` and `down` from an interactive terminal — `uc machine init` and `uc ctx` use a TUI that needs a TTY.

### Configuration (`tofu/terraform.tfvars`)

| Variable | Default | Notes |
|---|---|---|
| `domain` | — | your apex domain, e.g. `example.com` |
| `cloudflare_zone_id` | — | from the Cloudflare dashboard sidebar |
| `dns_apex` | `false` | also point the apex at the box (the `*.<domain>` wildcard is always created) |
| `node_count` | `1` | `3` for a WireGuard mesh |
| `server_type` | `cpx22` | x86 2 vCPU / 4 GB; `cax11` for ARM (`hcloud server-type list`) |
| `location` | `fsn1` | `nbg1`, `hel1`, `ash`, `hil`, `sin` |
| `ssh_key_name` | — | an SSH key already in your Hetzner project |

## Deploy apps

Give a service a `build:` section and `mise run deploy` runs the whole loop in one command: build locally, push only the **changed layers** over SSH, then roll out with health checks.

Domains are never hardcoded. Set yours once (`domain` in `tofu/terraform.tfvars`) and write `${DOMAIN}` in compose — `mise run deploy` reads it from tofu state and injects it. Any subdomain resolves via the wildcard record and is covered by the wildcard cert.

```yaml title="compose.yaml"
services:
  api:
    build: .
    x-ports:
      - api.${DOMAIN}:8080/https
```

```bash
mise run deploy               # build + push changed layers + rolling deploy
mise watch deploy             # re-deploy on every save
mise run push                 # build + push only (uc build --push)
mise run push your/api:1.2.3  # push an image built elsewhere (uc image push)
```

Local Docker (e.g. [OrbStack](https://orbstack.dev) on a Mac) is only the daemon `uc build` uses to build — the push is `uc`'s own.

### The registry

There is no registry to run. Uncloud embeds [unregistry](https://github.com/psviderski/unregistry) — "rsync for Docker images." On push, `uc` opens an SSH tunnel to each target machine, starts a temporary unregistry container, transfers only the layers that machine lacks, lands the image directly in its store, and removes the container. `uc machine init` enables Docker's **containerd image store** so pushed images are usable with no `docker pull` — which is why `cloud-init` leaves the Docker install to `uc`. On multi-node clusters the push goes to every machine running the service.

## Recipes

`mise run recipe <name>` deploys a service by name, resolving the repo's committed [`examples/`](examples/) **first**, then the upstream catalog:

```bash
mise run recipe            # list everything (local + upstream)
mise run recipe wordpress  # local example — WordPress + MariaDB at https://wordpress.<your-domain>
mise run recipe imgproxy   # local example — libvips image transforms at https://img.<your-domain>
mise run recipe nats       # upstream catalog
```

A recipe is a folder — `compose.yaml` plus any `.env`/config files — and `recipe` runs `uc deploy` from that folder so Uncloud finds the relative files. `recipe wordpress` derives its hostname from the cluster domain (override with `WP_DOMAIN=...`) and generates DB credentials; per-recipe wiring lives in `scripts/recipe.nu`. Add upstream sources in [`recipes.toml`](recipes.toml):

```toml
[[sources]]
name = "uncloud-recipes"
url  = "https://github.com/psviderski/uncloud-recipes"
```

## Tracking what's on what servers

| Source | Answers | Lives |
|--------|---------|-------|
| `uc machine ls` / `uc ls` | live machines + running services | while the cluster exists |
| `tofu/*.tfstate` | which cloud resources exist | while infra exists |
| `state/log.jsonl` | full up / deploy / down history | forever (git) |

`up`, `recipe`, and `down` append a timestamped JSON line to `state/log.jsonl`; `mise run status` shows all three layers. Commit the ledger to share the inventory.

### Remote state in R2

Move tofu state off your laptop into Cloudflare R2 — durable and lockable (OpenTofu's native lockfile, no DynamoDB):

```bash
mise run state:remote     # creates the vm-uncloud-tfstate bucket + migrates state to R2
```

Your `CLOUDFLARE_API_TOKEN` is the R2 credential: Cloudflare accepts `access_key_id = token id`, `secret = sha256(token)` for the R2 S3 API. `scripts/r2.nu` re-derives this at run time — nothing is stored — and `up`/`down`/`status` load it automatically. Needs `CLOUDFLARE_ACCOUNT_ID` in fnox and a token with R2 read/write. The generated `backend.tf`/`backend.hcl` are gitignored.

`tofu` authenticates with `HCLOUD_TOKEN`, which may target a different Hetzner project than your `hcloud` CLI context. Verify with `fnox exec -- hcloud server list`, not a bare `hcloud server list`.

## External services

Front non-container services — a BMC, HomeAssistant, a NAS, your `vm-servers` box — through the cluster's Caddy on your domain:

```bash
cp caddy/external.caddyfile.example caddy/external.caddyfile
$EDITOR caddy/external.caddyfile
mise run caddy:external
```

## Checks

`mise run ci` runs `tofu fmt` + `validate` and parses every script. The same command runs on every push via [`.github/workflows/check.yml`](.github/workflows/check.yml) — a thin wrapper around `mise run ci`, no logic in the YAML.

## Troubleshooting

**HTTPS cert missing.** Check Caddy on the box: `docker logs $(docker ps -qf name=caddy) 2>&1 | grep -iE 'acme|obtain|error'`. The Caddy service must be the `caddybuilds/caddy-cloudflare` image with `CLOUDFLARE_API_TOKEN` in its environment (`uc ls` to confirm). macOS can negative-cache a name from before the record existed — run `sudo dscacheutil -flushcache`, or test with `curl --resolve <host>:443:<ip>`.

**`could not open TTY`.** `uc machine init` and `uc ctx` need a real terminal — run from an interactive shell, not headless/CI.

**`context not found`.** The cluster context must match `$UNCLOUD_CONTEXT` (default `hetzner`); `mise run up` creates it with that name.
