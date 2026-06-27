# vm-uncloud

An [Uncloud](https://github.com/psviderski/uncloud) cluster on Hetzner, on your own
Cloudflare domain. Create it, deploy apps to `*.<domain>`, tear it down. The only
thing you install is [`mise`](https://mise.jdx.dev) — it provides every other tool,
including the `uc` CLI.

Runs **upstream** uncloud (v0.20, binary `uc`) and upstream images — no forks. One
tool, one provisioning idiom (OpenTofu + `fnox` keychain secrets), one cost ledger.

## Quickstart

You need a Cloudflare zone + API token (`Zone:DNS:Edit`) and a Hetzner project + SSH key.

```bash
mise install                                             # all tools, incl. the uc CLI
cp tofu/terraform.tfvars.example tofu/terraform.tfvars   # domain, cloudflare_zone_id, ssh_key_name
mise run secrets:set                                     # tokens -> macOS keychain (via fnox)
mise run cluster:up                                      # Hetzner box + wildcard DNS + cluster
mise run cluster:deploy                                  # deploy compose.yaml
mise run cluster:down                                    # destroy everything
```

Secrets live in the keychain, never on disk. TLS is one `*.<domain>` wildcard cert
via Cloudflare DNS-01, so any subdomain just works. `cluster:up` runs `uc machine
init` under a PTY + retry, so it works headless (CI, agents) too.

## Layout

The thing that's confusing at first is that almost every folder is just the code
behind a `mise` task. Here's the whole map.

| Folder | What's in it |
|---|---|
| `scripts/` | The nu scripts behind every task — cluster/recipe/arm/prices/dev/win/vultr lifecycle. One script per concern. |
| `recipes/` | One folder per deployable service: `compose.yaml` + optional `prepare.nu`. **Each recipe has its own README.** |
| `tofu/` | OpenTofu: provisions the Hetzner box(es), Cloudflare DNS, and the firewall. `terraform.tfvars` is your config. |
| `caddy/` | The wildcard-cert ingress (DNS-01) + the caddyfile for fronting non-container hosts. |
| `connect/` | Client-side helpers to reach a node — RDP, noVNC viewer, SSH, VS Code Remote. |
| `gui/` | The read-only web status board — one http-nu script (`gui/server/serve.nu`). |
| `state/` | The price catalogs and the deploy ledger (`*.jsonl`), plus the scripts that write them. |
| `tasks/` | A shared mise task lib other repos `include` (the remote-dev loop). |
| `mcp/` | MCP server config, so an LLM can call the nu tools. |
| `tofu/`, `cloud-init/`, `templates/`, `r2/` | Provisioning templates + R2 state-backend helpers. |

And the tasks, by namespace (`mise tasks` for the full list):

| `mise run …` | Does |
|---|---|
| `cluster:*` | provision / deploy / push / status / teardown the always-on cluster |
| `recipe:*` | deploy a service recipe — `recipe:deploy <name>` (remote) or `recipe:local <name>` |
| `arm:*` | Hetzner ARM (cax) capacity — check / list / grab / watch / adopt / evict / release |
| `prices:*` | refresh + show the price model |
| `dev:*` | ephemeral remote **dev** node — compile/test on a box that matches the deploy target |
| `win:*` · `win-kvm:*` | ephemeral **Windows** desktop node (Cloud TCG / bare-metal KVM) |
| `gui:*` · `xs:*` | the web status board + its event bus |
| `registry:*` · `ov-admin:*` | publish live service URLs into OrangeVault; admin client |
| `secrets:*` | tokens → keychain |
| `state:*` · `r2:*` | move tofu state into Cloudflare R2 (durable, lockable) |
| `caddy:*` | front external (non-container) hosts through the ingress |
| `turso:*` | the turso/libSQL recipe — see [`recipes/turso`](recipes/turso) |
| `moq:demo` | local Media-over-QUIC demo — see [`recipes/moq`](recipes/moq) |
| `cliff:*` | changelog / release intel |
| `mcp:*` · `ai:*` | run the MCP server / ask an LLM |
| `vultr:*` | Vultr bare-metal lifecycle (the `win-kvm` provider) |

Status, honestly: `cluster:*`, `recipe:*`, `arm:*`, `prices:*`, `gui:*` are
exercised. `dev:*` works; `win:*` (TCG) works; **`win-kvm:*`, `registry:*`, and
`dev-win` are scaffolded** — they need a live run to verify (flagged in their
sections below). Everything is nushell so it's OS-neutral and CI parse-checks it.

## Config — `tofu/terraform.tfvars`

| Variable | Default | |
|---|---|---|
| `domain` | — | your apex, e.g. `example.com` |
| `cloudflare_zone_id` | — | Cloudflare dashboard sidebar |
| `ssh_key_name` | — | an SSH key already in your Hetzner project |
| `node_count` | `1` | `3` for a mesh |
| `server_type` | `cpx22` | `cax11` = ARM |
| `location` | `fsn1` | `nbg1` `hel1` `ash` `hil` `sin` |
| `dns_apex` | `false` | also point the apex at the box |

## Deploy

Use `${DOMAIN}` in compose — never hardcode the host; `cluster:deploy` injects it.

```yaml
services:
  api:
    build: .
    x-ports: ["api.${DOMAIN}:8080/https"]
```

```bash
mise run cluster:deploy        # build + push changed layers + roll out
mise watch cluster:deploy      # re-deploy on save
mise run cluster:push [image]  # push only — uc's built-in registry, no docker pull
```

Building needs local Docker (OrbStack on a Mac). Match the server arch: `cpx22` is
x86, so build `linux/amd64` (`platform: linux/amd64`), or use `cax11` ARM nodes to
match an Apple-silicon Mac.

> **Teardown granularity:** `cluster:down` is whole-node (tofu destroy) — right for
> the ephemeral nodes, but there's no clean "remove one recipe, keep the rest" yet
> (uncloud [#369](https://github.com/psviderski/uncloud/issues/369)). For now,
> per-service removal is `uc rm <service>`.

## Recipes

A recipe is a folder under [`recipes/`](recipes/): `compose.yaml` + an optional
`prepare.nu` that generates and persists its own secrets. Adding one touches no
shared code. Each recipe documents itself in its own `README.md`.

```bash
mise run recipe:deploy                  # list available
mise run recipe:deploy wordpress        # WordPress + MariaDB
mise run recipe:deploy moltis           # self-hosted AI agent server
mise run recipe:deploy imaginary        # libvips image API
mise run recipe:local rauthy            # run a recipe locally via plain docker compose
```

Recipes the repo ships beyond the built-ins: `moq` (Media over QUIC),
`rauthy` (OIDC), `turso` (self-hosted libSQL/SQLite). Upstream recipe sources are
listed in [`recipes.toml`](recipes.toml) and cloned on demand (`recipe:sync`).

## Node classes

One repo, one tool — but not one node. Workloads differ in size, burst, and
whether they need real virtualization. Each ephemeral class is its **own uncloud
context** (separate tofu state + `up`/`down`), independent of the live cluster.

| Class | SKU | Virt | Lifecycle | For |
|---|---|---|---|---|
| **cluster** | Hetzner `cpx22` | container | always-on | web containers, Moltis. **Live.** |
| **dev** | `cpx42`/`cax*` | container | ephemeral | remote dev container that matches the deploy target |
| **win-batch** | `cpx42` | dockur **TCG** | ephemeral | Windows batch/unattended; ~10× slower than KVM, cheap |
| **win-kvm** | Vultr bare metal | dockur **KVM** | ephemeral | interactive Windows. **Scaffolded** — needs a Vultr key + live run |
| **dev-win** | `cpx42` | dockur TCG | ephemeral | remote dev on real Windows. **Experimental** |

Hetzner **Cloud** has no `/dev/kvm` on any tier, so KVM-fast needs bare metal
(Vultr hourly, or Hetzner Robot `ax*` with a 30-day minimum) — which the Cloud tofu
provider can't reach. That's why `win-batch` is TCG and `win-kvm` is a separate
path. Firewall: the cluster opens `22/80/443/51820`; each other class adds its own
rule (Windows `:3389`, dev the SSH port), restricted to `ssh_allowed_ips`.

## ARM capacity (`arm:*`)

ARM (`cax`) is offered **only** in the 3 EU sites (nbg1/hel1/fsn1) and is frequently
100% sold out. These tools grab it the moment it appears. Hetzner is the source of
truth — no local record is kept.

```bash
mise run arm:check                 # availability (✓ available / ✗ sold out / — no ARM here)
mise run arm:list                  # the cax boxes we hold (name, type, DC, IP, created)
mise run arm:watch:up              # supervised watcher: 5s poll, AUTO-GRABS up to 1 per EU DC (max 3)
mise run arm:watch:down            # stop it
mise run arm:adopt -- <loc>        # join a held box INTO the cluster (uc machine add)
mise run arm:evict -- <loc>        # remove from cluster but KEEP the box (re-adoptable)
mise run arm:release-all           # delete the boxes (stops billing)
```

Lifecycle of a scarce box: **grab → adopt ⇄ evict → release**. The watcher runs
under pitchfork so it survives sessions; it auto-grabs (spends money) the moment
stock appears, capped at one box per EU DC.

## Remote dev (`dev:*`)

Keep your repo on your Mac; compile/test it on a box that matches the deploy target
(real `linux/amd64`). The dev environment is just the `dev-linux` recipe (base +
mise + sshd).

```bash
cp tofu/dev.tfvars.example tofu/dev.tfvars
mise run dev:up        # provision a teardownable Linux dev node (dev context)
mise run dev:deploy    # build + deploy dev-linux onto it
mise run dev:ssh:wait  # wait for SSH, then:
mise run dev:code      # VS Code Remote-SSH into /workspace   (or dev:ssh)
mise run dev:down      # destroy when idle
```

From a **project** repo, include the shared task lib (mise pulls just the one file)
and drive the loop with your own build/test tasks. The shared tasks are namespaced
`uncloud:dev:*` so they can't clash:

```toml
[task_config]
includes = ["git::https://github.com/joeblew999/vm-uncloud.git//tasks/dev.toml?ref=<tag>"]
```

```bash
mise run uncloud:dev:build     # rsync the repo to the node + run its `mise run build` there
mise run uncloud:dev:release   # build + docker + GitHub release, on the node
```

Dev secrets come from a dedicated [OrangeVault](https://github.com/joeblew999/orangevault)
account via fnox (`dev:secrets:set` → `dev:secrets:check`).

## Windows desktops (`win:*`)

`dockur/windows` is just a container, so it's an uncloud recipe — no bespoke
lifecycle. It runs on its own dedicated, teardownable node (never on the cluster).

```bash
cp tofu/win-batch.tfvars.example tofu/win-batch.tfvars
mise run win:up           # provision the cpx42 Windows node (RDP :3389 opened)
mise run win:deploy       # deploy dockur/windows
mise run win:rdp:wait     # wait until install finishes (notifies)
mise run win:rdp          # RDP in (user Docker / pass admin) — or win:viewer (noVNC tunnel)
mise run win:down         # snapshot THEN destroy → stops billing; win:up restores
```

`KVM=N` on Hetzner Cloud (TCG, ~5–10× slower). KVM-fast = bare metal via `win-kvm:*`
(Vultr BM) — scaffolded, needs `VULTR_API_KEY` + a first live run. Vultr BM has no
hot-snapshot, so `win-kvm:down` loses state today; for state-preserving on-demand
Windows, use `win-batch` (Hetzner snapshot).

## Service registry

When a recipe deploys, `recipe:deploy` can record its public URL in OrangeVault as a
Bitwarden login item, so any repo with the orangevault fnox provider resolves it by
name — no bespoke discovery. DNS gives the address; OrangeVault gives the catalog +
the secrets DNS can't.

- name `vmu/<context>/<service>` (e.g. `vmu/hetzner/moltis`), `uri` = the live URL.
- Opt in with `VMU_REGISTRY=1`; best-effort and self-guarding (no creds → no-op,
  never breaks a deploy). **Experimental** — exercise the manual `registry:publish`/
  `registry:list`/`registry:remove` tasks once before turning on auto-publish.

```toml
# a consumer project's fnox.toml
MOLTIS_URL = { provider = "orangevault", value = "vmu/hetzner/moltis/uri" }
```

## State, prices, GUI

```bash
mise run cluster:status   # machines, services, history
mise run state:remote     # move tofu state to Cloudflare R2 (durable, lockable)
mise run prices:show      # the merged price model as a table
mise run gui:up           # web status board -> http://127.0.0.1:8080  (gui:down to stop)
```

`state/log.jsonl` is the up/deploy/down ledger (in git). The price model is
`state/prices-*.jsonl`, one live catalog per class, each owned by a refresh task
(`prices:refresh:hetzner-cloud` from the hcloud API; `:hetzner-dedicated` and
`:hetzner-auction` from the Robot API, needing `HETZNER_ROBOT_USER`/`_PASSWORD` in
the keychain). Dedicated has two worlds: new-order (64 GB ≈ €187/mo) vs the auction
floor (used, 64 GB ≈ €46/mo). `tofu` reads `HCLOUD_TOKEN` via fnox — verify infra
with `fnox exec -- hcloud server list`, not bare `hcloud`.

The GUI (`gui/server/serve.nu`, one http-nu + Datastar closure, supervised by
pitchfork) shows nodes, services, snapshots, prices, and the ledger. Read-only today.

## Gotchas

- **uncloud is `uc` since v0.20** (binary renamed from `uncloud`; daemon stays
  `uncloudd`). On a machine's first boot the daemon pulls the Corrosion **Docker
  image**, which can exceed systemd's start timeout → `uc machine init/add` fail
  once, the daemon auto-restarts and comes up. Intermittent — `cluster-up.nu` and
  `arm.nu` retry through it. The gRPC proxy format changed in 0.20, so the CLI and
  all machines must share a major; upgrade with no cluster running.
- **uncloud appends a trailing `\n` to every injected env value.** Harmless except
  for exact-match values — it broke the Cloudflare token for Caddy's DNS-01 (no
  cert). Strip CR/LF in the consuming container (the caddy recipe does this with
  `tr -d`). Upstream-tracked.
- **`uc machine init`'s readiness spinner wants a TTY** — dies headless. The PTY
  wrapper in `cluster-up.nu` fixes it ([#386](https://github.com/psviderski/uncloud/issues/386)).
- **`ssh-add ~/.ssh/<key>` before `cluster:up`** if the agent is empty, or init
  can't key-auth as root.
- Run `cluster:up`/`down` from a **real terminal** (down prompts for the cluster
  name unless `--yes`, and aborting leaves the box **billing** — delete, don't stop).

## Checks

`mise run ci` runs the same checks locally and in CI (every push, via
`.github/workflows/check.yml`): tofu fmt/validate, parse every nu script, run each
`prepare.nu`, parse the composes. Nushell is the scripting language throughout —
chosen for OS-neutrality; no hardcoded paths, no bash-isms.

---

Supersedes the old [vm-servers](https://github.com/joeblew999/vm-servers) repo
(bespoke hcloud + cloud-init lifecycle). Sibling
[vm-software](https://github.com/joeblew999/vm-software) holds the Windows
installers that run *inside* the guest.
