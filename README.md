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
mise run recipe windows          # Windows desktop (dockur/windows) — see Virtual desktops
mise run recipe wordpress-galera # EXPERIMENTAL — multi-master (needs node_count >= 3)
```

A recipe is a folder: `compose.yaml` + optional `prepare.nu` (generates and persists its own secrets). Adding one touches no shared code.

## State

```bash
mise run status        # machines, services, history
mise run state:remote  # move tofu state to Cloudflare R2 (durable, lockable)
```

`state/log.jsonl` is the up/deploy/down ledger (in git). `tofu` uses `HCLOUD_TOKEN` — verify infra with `fnox exec -- hcloud server list`, not bare `hcloud`.

## Web GUI

A browser status board (Hetzner nodes, uncloud services, snapshots, the cost
model, and the deploy ledger) served by http-nu + Datastar, supervised by
pitchfork. Read-only today; actions (deploy/win lifecycle) are the next layer.

```bash
mise run gui:up      # start the GUI + xs event bus → http://127.0.0.1:8080
mise run gui:down    # stop them
mise run gui:serve   # foreground (hot-reloads on serve.nu edits)
```

`gui/server/serve.nu` is the whole app (one http-nu closure). Same stack as the
old vm-servers board, pointed at uncloud/hcloud data instead of a single VM.

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

## Virtual desktops (Windows)

This repo is the **single home for our Hetzner deployments** — one tool
(uncloud), one provisioning idiom (tofu + `fnox` secrets), one cost ledger. That
includes virtual desktops: **`dockur/windows` is just a container, so it runs as
an uncloud recipe** — no bespoke parallel lifecycle.

Windows is heavy + bursty, so it runs on its **own dedicated, teardownable node**
(`win-batch` — a `cpx42` in its own tofu workspace + uncloud context), never on
the always-on `cpx22` cluster. The whole cycle (`state/costs.jsonl` has pricing):

```bash
cp tofu/win-batch.tfvars.example tofu/win-batch.tfvars   # one-time
mise run win:up           # provision the cpx42 Windows node (RDP :3389 opened)
mise run win:deploy       # deploy dockur/windows onto it
mise run win:rdp:wait     # wait until Windows finishes install (notifies)
mise run win:rdp          # RDP in (user Docker / pass admin) — or win:viewer (noVNC tunnel)
mise run win:down         # snapshot THEN destroy → stops billing; win:up restores
```

`KVM=N` on Hetzner Cloud (TCG, ~5-10× slower). **KVM-fast = bare metal** via the
`win-kvm:*` tasks (Vultr BM; Hetzner Cloud has no `/dev/kvm`) — scaffolded, needs
a Vultr key + a first live run. See [`docs/PLACEMENT.md`](docs/PLACEMENT.md) for
the node-class-per-workload map.

Supersedes the old standalone [vm-servers](https://github.com/joeblew999/vm-servers)
repo (bespoke hcloud + cloud-init lifecycle). Sibling
[vm-software](https://github.com/joeblew999/vm-software) — the Windows installers
that run *inside* the guest (different execution context, stays separate).
