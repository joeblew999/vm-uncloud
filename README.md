# vm-uncloud

**Spin up an [Uncloud](https://github.com/psviderski/uncloud) cluster on a Hetzner VPS, served on your own Cloudflare domain — with three commands.**

It provisions the server, points your domain at it, installs Uncloud, and deploys your apps. Tear it all down just as fast. Glued together with `mise` + `nushell`, secrets from `fnox`/keychain.

```bash
mise install        # tools: opentofu, hcloud, nushell
mise run setup      # install the uncloud CLI locally
mise run up         # create VPS + DNS + cluster
mise run deploy     # deploy compose.yaml
mise run down       # destroy everything, cleanly
```

## What this is for (and what it isn't)

This repo is the **Linux container-hosting** member of the `vm-*` family. Each one does a different job — keep them straight:

| Repo | What it's for |
|------|---------------|
| **[vm-uncloud](https://github.com/joeblew999/vm-uncloud)** (this) | Host **Linux web apps / containers** — Uncloud cluster on Hetzner + Cloudflare DNS + auto-HTTPS. Deploy via Docker Compose. |
| [vm-servers](https://github.com/joeblew999/vm-servers) | Run **Windows in a VM** — Mac control plane, Hetzner/Vultr drivers, R2 snapshot pipeline. |
| [vm-software](https://github.com/joeblew999/vm-software) | Catalog of **Windows software installers**, git-cloned inside a vm-servers VM. |

If you want to run a containerised web service on your own domain, you're in the right place. If you need a Windows desktop/app VM, use `vm-servers`.

## How it works

Uncloud installs itself onto a fresh Linux box **over SSH** — you never copy binaries up. So locally you only need the `uncloud` CLI. The gaps the CLI doesn't cover — *creating the box* and *pointing your domain at it* — are what the OpenTofu config here does. Uncloud's bundled **Caddy** then terminates TLS with Let's Encrypt per hostname, so a plain Cloudflare `A` record is all you need.

| Where | What | Installed by |
|-------|------|--------------|
| Your machine | `uncloud` CLI (`uc`), `docker-pussh` | `mise run setup` |
| Hetzner box | Docker + `uncloudd` | `cloud-init/uncloud.yaml` on first boot |
| Hetzner box | WireGuard mesh, Caddy, cluster | `uc machine init` over SSH |
| Cloudflare | `A` records → ingress node | OpenTofu |

WireGuard ships in the kernel; `corrosion` (cluster state) is bundled in `uncloudd`; `unregistry` is pulled on-demand by `docker pussh`.

## Setup

**Prerequisites:** a Cloudflare zone + token (`Zone:DNS:Edit`), a Hetzner project + SSH key, `mise`.

```bash
mise install
mise run setup

cp tofu/terraform.tfvars.example tofu/terraform.tfvars
$EDITOR tofu/terraform.tfvars     # domain, cloudflare_zone_id, ssh_key_name, hostnames

mise run secrets:set              # seeds HCLOUD_TOKEN + CLOUDFLARE_API_TOKEN (skips if set)
mise run up
```

Secrets live in the macOS keychain (service `fnox`, shared with `vm-servers`) and are injected by `fnox exec`; the OpenTofu providers read `HCLOUD_TOKEN` / `CLOUDFLARE_API_TOKEN` straight from the environment — never written to disk. SSH uses `~/.ssh/gedw99_hetzner`.

> **Run `up`/`down` from a real terminal.** `uc machine init`/`uc ctx` use an interactive TUI that needs a TTY. The scripts pass `-y` so provisioning still completes headless; only the progress UI needs the TTY.

## Configuration (`tofu/terraform.tfvars`)

| Variable | Default | Notes |
|---|---|---|
| `domain` | — | your apex domain, e.g. `amplifycms.net` |
| `cloudflare_zone_id` | — | Cloudflare dashboard sidebar |
| `app_hostnames` | `["app"]` | A records → ingress node; `"@"` = apex |
| `node_count` | `1` | `3` for a WireGuard mesh |
| `server_type` | `cpx22` | x86 2vCPU/4GB; `cax11` ARM. `hcloud server-type list` |
| `location` | `fsn1` | `nbg1`, `hel1`, `ash`, `hil`, `sin` |
| `ssh_key_name` | — | name of an SSH key in your Hetzner project |

## Deploy apps

Reference hostnames you created in `app_hostnames`:

```yaml title="compose.yaml"
services:
  api:
    image: your/api:latest
    x-ports:
      - api.amplifycms.net:8080/https
```
```bash
mise run deploy
docker pussh your/api:latest root@<node-ip>   # push private images, no registry
```

## Where do apps live? (this repo vs yours)

This repo is the **platform** — it stands up clusters and knows how to deploy onto them. It is *not* where your apps live:

- **Demo/recipe apps** (like WordPress) are **referenced, never vendored.** `mise run recipe <name>` pulls them from upstream recipe repos into `.src/` (gitignored) at deploy time. Nothing app-specific is committed here.
- **Your real apps** keep their own `compose.yaml` in their own repo, and you deploy it with `uc deploy -f path/to/compose.yaml` (or copy this repo's `deploy` pattern). Keeps the platform reusable and your app history with the app.

## Examples (recipes)

Ready-made services from recipe repos — see [`examples/`](examples/):

```bash
mise run recipe                     # list available recipes
mise run recipe wordpress-mariadb   # deploy one
```

**Adding more is one line.** Recipe sources live in [`recipes.toml`](recipes.toml) — a list of git repos laid out as `<name>/compose.yaml`. `recipe` clones each into `.src/` and searches them in order, so you can mix the upstream [uncloud-recipes](https://github.com/psviderski/uncloud-recipes) with your own:

```toml
[[sources]]
name = "uncloud-recipes"
url  = "https://github.com/psviderski/uncloud-recipes"

[[sources]]
name = "my-recipes"
url  = "https://github.com/joeblew999/my-uncloud-recipes"
```

## Tracking what's on what servers

Three layers, each the right tool for its question:

| Source | Answers | Lives |
|--------|---------|-------|
| `uc machine ls` / `uc ls` | live machines + running services | while the cluster exists |
| `tofu/*.tfstate` | exactly which cloud resources exist | while infra exists |
| `state/log.jsonl` | full up/deploy/down **history** | forever (git) |

`up`, `recipe`, and `down` append typed events to [`state/log.jsonl`](state/) automatically. `mise run status` shows all three. Commit the ledger to share the inventory.

## External services (bare metal, BMC, home hubs)

Front non-container services (a BMC, HomeAssistant, a NAS, your `vm-servers` box) through the cluster's Caddy on your domain:

```bash
cp caddy/external.caddyfile.example caddy/external.caddyfile
$EDITOR caddy/external.caddyfile
mise run caddy:external
```
