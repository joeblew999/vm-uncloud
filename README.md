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

## Scope & the vm-* family

This repo is the **single home for our Hetzner deployments** — one provisioning
idiom (tofu + `fnox` secrets), one cost ledger, no per-project bespoke scripts.
It hosts **two lifecycle modes** that share that base but stay deliberately
separate, because their cost models are opposite:

| Mode | Workload | Lifecycle | Cost posture |
|---|---|---|---|
| **cluster** (here today) | Linux containers — Moltis, WordPress, any web service | **always-on** uncloud node; many services, each on a `*.<domain>` subdomain | one small node 24/7 (`cpx22` ≈ €7.55/mo) |
| **vm** (folding in from [vm-servers](https://github.com/joeblew999/vm-servers)) | Windows desktop — Revit + Revit Batch Processor via [dockur/windows](https://github.com/dockur/windows) | **ephemeral**: provision → run batch → snapshot → destroy | ~€0.48/mo idle; pay the big box only while a batch runs |

**Why Windows is NOT an uncloud service.** dockur/windows is a container, so uncloud
*could* run it — but it shouldn't: it needs `/dev/kvm` for usable speed (Hetzner
Cloud has none → TCG-slow), uncloud has no disk-snapshot for the Windows state, and
co-hosting it on the shared always-on node would force that node up to `cpx42` 24/7
— a cost blow-out. So the `vm` mode keeps its own snapshot→destroy VM and RDP, and
just shares this repo's provisioning + secrets + cost ledger. uncloud is used where
it shines (containers), not contorted to host a VM.

Sibling: [vm-software](https://github.com/joeblew999/vm-software) — the Windows
installers that run *inside* the guest (different execution context, stays separate).
