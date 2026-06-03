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

Uncloud installs itself onto a fresh Linux box **over SSH** — you never copy binaries up. So locally you only need the `uncloud` CLI. The gaps the CLI doesn't cover — *creating the box* and *pointing your domain at it* — are what the OpenTofu config here does.

**TLS is wildcard + DNS-01, on purpose.** Caddy (the `caddybuilds/caddy-cloudflare` image, which bundles the Cloudflare DNS plugin) obtains **one `*.<domain>` wildcard certificate** via the Cloudflare DNS-01 challenge. That means:

- a single wildcard `A` record (`*.<domain>` → ingress node) covers every subdomain — no per-host DNS setup;
- **no HTTP-01** — no dependency on port 80 reachability or DNS propagation timing;
- **nothing to poll for** — the cert is issued once at cluster bring-up and covers any subdomain you later publish, instantly;
- **no Let's Encrypt rate-limit churn** from requesting a fresh cert per hostname on every deploy.

(This is why we *didn't* stick with per-host HTTP-01: the cert failures, the propagation waits, and the rate-limit churn are all symptoms of it.)

| Where | What | Installed by |
|-------|------|--------------|
| Your machine | `uncloud` CLI (`uc`), `docker-pussh` | `mise run setup` |
| Hetzner box | Docker + `uncloudd` | `cloud-init/uncloud.yaml` on first boot |
| Hetzner box | WireGuard mesh, cluster | `uc machine init` over SSH |
| Hetzner box | Wildcard/DNS-01 Caddy ingress | `caddy/compose.yaml` (deployed by `up`) |
| Cloudflare | `*.<domain>` wildcard `A` record | OpenTofu |

WireGuard ships in the kernel; `corrosion` (cluster state) is bundled in `uncloudd`; `unregistry` is pulled on-demand by `docker pussh`. The Cloudflare token is placed on the box for DNS-01 — scope it to `Zone:DNS:Edit` for your zone only.

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
| `dns_apex` | `false` | also create an `A` record for the apex (a `*.<domain>` wildcard is always created) |
| `node_count` | `1` | `3` for a WireGuard mesh |
| `server_type` | `cpx22` | x86 2vCPU/4GB; `cax11` ARM. `hcloud server-type list` |
| `location` | `fsn1` | `nbg1`, `hel1`, `ash`, `hil`, `sin` |
| `ssh_key_name` | — | name of an SSH key in your Hetzner project |

## Deploy apps

Pick any subdomain — the wildcard record + wildcard cert mean it just works, no extra setup:

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

## Troubleshooting

**HTTPS cert.** Issuance is one wildcard `*.<domain>` cert via Cloudflare DNS-01, obtained at cluster bring-up — no per-host waiting. If it's missing, check Caddy on the box:
- `docker logs $(docker ps -qf name=caddy) 2>&1 | grep -iE 'acme|obtain|error'`.
- DNS-01 needs the `CLOUDFLARE_API_TOKEN` (scoped `Zone:DNS:Edit`) present in the Caddy container env — `up` injects it; confirm with `uc ls` that the `caddy` service is the `caddybuilds/caddy-cloudflare` image.
- macOS may *negative-cache* a name from before the record existed, so `curl` fails to resolve even when `dig +short <host> @1.1.1.1` works: `sudo dscacheutil -flushcache` or test with `curl --resolve <host>:443:<ip>`.

> Earlier versions of this repo used per-host **HTTP-01**, which is where the `tlsv1 alert internal error` / `000-on-:443` / rate-limit-churn symptoms came from. The wildcard/DNS-01 setup above is the fix — if you somehow revert to HTTP-01, those symptoms return.

**`uc machine init` errors with `could not open TTY`.** Its progress UI needs a real terminal. Run `mise run up` from an interactive shell, not a headless/CI context (the scripts already pass `-y`).

**`context not found` on deploy/recipe/down.** The cluster context must match `$UNCLOUD_CONTEXT` (default `hetzner`). `mise run up` creates it with the right name via `--context`; if you ran `uc machine init` by hand, pass `--context hetzner`.

## On Cloudflare's new `cf` CLI

[Cloudflare's `cf`](https://blog.cloudflare.com/cf-cli-local-explorer/) (the planned successor to Wrangler) is an **early technical preview** — `npx cf` / `npm i -g cf` (npm, not Bun). It does **not** manage DNS records yet, so it can't replace the OpenTofu Cloudflare provider used here. Worth revisiting once DNS support lands; until then DNS stays in `tofu/`.
