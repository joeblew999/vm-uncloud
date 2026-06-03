# vm-uncloud

**Spin up an [Uncloud](https://github.com/psviderski/uncloud) cluster on a Hetzner VPS, served on your own Cloudflare domain — with three commands.**

It provisions the server, points your domain at it, installs Uncloud, and deploys your apps. Tear it all down just as fast. Glued together with `mise` + `nushell`, secrets from `fnox`/keychain. **The only hard requirement on your machine is [`mise`](https://mise.jdx.dev)** — plus local Docker (e.g. [OrbStack](https://orbstack.dev) on a Mac) *if* you build and push your own images.

```bash
mise install        # fetches opentofu, hcloud, nushell, fnox
mise run setup      # installs the uncloud CLI (uc)
mise run up         # create VPS + wildcard DNS + cluster
mise run deploy     # deploy compose.yaml   (or: mise run recipe wordpress)
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
| Your machine | `uncloud` CLI (`uc`) | `mise run setup` |
| Hetzner box | Docker + `uncloudd` | `cloud-init/uncloud.yaml` on first boot |
| Hetzner box | readiness gate (SSH up + cloud-init done) | tofu `remote-exec` provisioner — `apply` blocks until ready, **no shell polling** |
| Hetzner box | WireGuard mesh, cluster | `uc machine init` over SSH |
| Hetzner box | Wildcard/DNS-01 Caddy ingress | `caddy/compose.yaml` (deployed by `up`) |
| Cloudflare | `*.<domain>` wildcard `A` record | OpenTofu |

WireGuard ships in the kernel; `corrosion` (cluster state) is bundled in `uncloudd`; the image registry (`unregistry`) is built into uncloud — `uc build --push` / `uc image push` ship local images to the cluster, no external registry. The Cloudflare token is placed on the box for DNS-01 — scope it to `Zone:DNS:Edit` for your zone only.

## Requirements — just `mise`

The only thing you install on your machine is **[mise](https://mise.jdx.dev)**. `mise install` pins and fetches everything else — `opentofu`, `hcloud`, `nushell`, `fnox` — and `mise run setup` adds the `uncloud` CLI (`uc`). (`git`, `ssh`, and `curl` are assumed — every dev box has them.)

**Local Docker is optional, and only for building your own images.** Public-image recipes (the WordPress demo, etc.) need no local Docker — the Hetzner box pulls them. To ship *your own* app, Uncloud has the registry **built in** (unregistry) — one command builds locally and pushes straight to the cluster machines, no external registry, only the missing layers transfer:

```shell
uc build --push                      # build Compose services locally + push to the cluster
# or push an image you already built:
uc image push myapp:1.2.3
```

On a Mac, **[OrbStack](https://orbstack.dev)** (or Docker Desktop / Colima) is the local Docker daemon `uc build` uses for the build step. No `docker pussh` plugin needed — `uc` does it.

You provide: a **Cloudflare** zone + API token (`Zone:DNS:Edit`, plus R2 if you want remote state), and a **Hetzner** project + an SSH key.

## Setup

```bash
mise install                      # opentofu, hcloud, nushell, fnox
mise run setup                    # installs the uncloud CLI (uc)

cp tofu/terraform.tfvars.example tofu/terraform.tfvars
$EDITOR tofu/terraform.tfvars     # domain, cloudflare_zone_id, ssh_key_name

mise run secrets:set              # seeds HCLOUD_TOKEN + CLOUDFLARE_API_TOKEN (skips if set)
mise run up
```

Secrets live in the macOS keychain (service `fnox`) and are injected by `fnox exec`; the OpenTofu providers read `HCLOUD_TOKEN` / `CLOUDFLARE_API_TOKEN` straight from the environment — never written to disk. SSH uses `~/.ssh/gedw99_hetzner`.

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

## Deploy apps — and the fast update loop

The best integration is **one command**. Give a service a `build:` section and `mise run deploy` does the whole loop — build locally, push only the **changed layers** over SSH (uncloud's built-in registry — no external registry, no rebuild on the server), then roll out with health checks. Pick any subdomain; the wildcard record + cert already cover it.

```yaml title="compose.yaml"
services:
  api:
    build: .                          # your Dockerfile
    x-ports:
      - api.amplifycms.net:8080/https
```
```bash
mise run deploy        # build (local Docker) + push changed layers + rolling deploy — one command
```

**Continuous iteration** — re-deploy on every save via mise's built-in watcher:

```bash
mise watch deploy
```

**Just push, don't deploy** (pre-warm layers, or ship an image built elsewhere):

```bash
mise run push                 # uc build --push
mise run push your/api:1.2.3  # uc image push <image>
```

Local Docker (e.g. [OrbStack](https://orbstack.dev) on a Mac) is only the daemon `uc build` uses — the push is `uc`'s own, no plugin.

### How the registry works (there isn't one)

There's **no registry to run or pay for**. uncloud embeds [unregistry](https://github.com/psviderski/unregistry) — "rsync for Docker images." When you push, `uc`:

1. opens an SSH tunnel to each target machine,
2. starts a **temporary** unregistry container there,
3. `docker push`es through the tunnel, transferring **only the layers the machine doesn't already have**,
4. the image lands directly in the machine's image store, instantly usable,
5. tears the temporary container down.

This works because `uc machine init` installs Docker with the **containerd image store** enabled (`containerd-snapshotter`), so pushed images are usable with no extra `docker pull`. (That's also why `cloud-init` here does *not* pre-install Docker — letting `uc` install it fresh guarantees the containerd store is on.) On multi-node clusters the push goes to every machine that runs the service. Nothing persistent, no external registry, no credentials to manage.

**Where apps live:** keep the `compose.yaml` + `Dockerfile` in the app's own repo and target the cluster with `uc deploy -c hetzner` (or `UNCLOUD_CONTEXT`). `vm-uncloud` is the platform; apps deploy onto it.

## Where do apps live? (this repo vs yours)

This repo is the **platform** — it stands up clusters and knows how to deploy onto them. It is *not* where your apps live:

- **Example apps** (like WordPress) live in [`examples/`](examples/) — committed, visible, yours to edit.
- **Your real apps** keep their own `compose.yaml` in their own repo, deployed with `uc deploy -f path/to/compose.yaml`. Keeps the platform reusable and your app history with the app.

## Demo: WordPress in two commands

```bash
mise run up                 # cluster + wildcard DNS/cert on your domain
mise run recipe wordpress   # WordPress + MariaDB, published at https://wordpress.<your-domain>
```

That's it — `recipe wordpress` deploys [`examples/wordpress/compose.yaml`](examples/wordpress/compose.yaml), auto-derives the hostname (`wordpress.<your-domain>`) from the cluster, generates DB credentials, and the wildcard cert already covers it. Browse to `https://wordpress.<your-domain>`. Override the hostname with `WP_DOMAIN=blog.<your-domain> mise run recipe wordpress` if you like.

## Recipes

`mise run recipe <name>` deploys by name, checking this repo's committed [`examples/`](examples/) **first**, then the upstream catalog:

```bash
mise run recipe            # list everything available (examples + upstream)
mise run recipe wordpress  # local example
mise run recipe nats       # upstream catalog
```

**Adding more is one line.** Upstream sources live in [`recipes.toml`](recipes.toml) — git repos laid out as `<name>/compose.yaml`, cloned into `.src/` on demand. Mix the upstream [uncloud-recipes](https://github.com/psviderski/uncloud-recipes) with your own:

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

### Remote tofu state in R2 (recommended)

By default tofu state is local — fine for one operator, but it can't be shared and, if lost, leaves orphaned billable resources. Move it to Cloudflare R2 (durable, lockable via OpenTofu 1.10's native lockfile — no DynamoDB) with one command:

```bash
mise run state:remote     # creates the vm-uncloud-tfstate bucket + migrates local state to R2
```

No separate R2 token needed — your **`CLOUDFLARE_API_TOKEN` is the R2 credential**: Cloudflare accepts `access_key_id = token id`, `secret = sha256(token)` for the R2 S3 API. `scripts/r2.nu` re-derives that at run time (nothing stored), and `up`/`down`/`status` load it automatically once the remote backend is active. Requirements: the token must have **R2 read/write** permission, and `CLOUDFLARE_ACCOUNT_ID` in fnox. `backend.tf`/`backend.hcl` are generated and gitignored.

> **Heads-up — `hcloud` token vs project.** tofu authenticates with `HCLOUD_TOKEN` from fnox, which may target a *different* Hetzner project than your `hcloud` CLI context. Always verify with `fnox exec -- hcloud server list` (same token tofu uses), not a bare `hcloud server list`, or you'll be looking at the wrong project.

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
