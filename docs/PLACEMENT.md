# Placement — which node class runs which workload

One repo, one tool (uncloud). But not one node: workloads differ in size, burst,
and whether they need real virtualization (KVM). This is the map. Pricing is in
`state/costs-*.jsonl` (`mise run costs:show`).

## Node classes

| Class | Provider / SKU | Virt | Lifecycle | For |
|---|---|---|---|---|
| **cluster** | Hetzner Cloud `cpx22` (2/4) | container | **always-on** | Moltis + light web containers. **LIVE** (`amplifycms.com`). |
| **win-batch** | Hetzner Cloud `cpx42` (8/16) | dockur **TCG** (`KVM=N`) | **ephemeral**: up → `recipe windows` → snapshot → down | Windows batch / unattended (Revit RBP). ~10× slower than KVM, but cheap & hourly. **NEXT TO BUILD.** |
| **win-kvm** | Vultr Bare Metal (hourly) or Hetzner Robot `ax*` | dockur **KVM** (`/dev/kvm`) | ephemeral (Vultr) / 30-day-min (Robot) | Interactive Windows where TCG is too slow. **SCAFFOLDED** (`win-kvm:*`; needs a Vultr key + live run). |
| **dev** | Hetzner Cloud `cpx42`/`cpx32` (x86; `cax*` for ARM) | container | **ephemeral**: `dev:up` → `dev:deploy` → work → `dev:down` | Remote dev container (`dev-linux`): compile/test a project on a box that matches the deploy target. SSH-only (dev port), no wildcard. See [`DEVCONTAINERS.md`](DEVCONTAINERS.md). |
| **dev-win** | Hetzner Cloud `cpx42` (8/16) | dockur **TCG** (`KVM=N`) | ephemeral: `dev:up:win` → `dev:deploy:win` → work → `dev:down:win` | Remote dev on real Windows (`dev-windows` = `windows` + mise/git/OpenSSH via `/oem`). Both `windows = true` **and** `dev = true`. **EXPERIMENTAL** (guest SSH unverified). |

**Rule:** never co-locate Windows on the `cluster` node (it's a 2/4 box; Windows
needs 8/16+). Each Windows node is **dedicated and teardownable** so it's billed
only while in use — `hcloud` snapshot then destroy when idle, re-provision from
snapshot to resume. Same economics as the old vm-servers `start`/`stop`, via
uncloud `up`/`down` + the windows recipe.

## The KVM caveat (why win-kvm is a separate path)

Hetzner **Cloud** exposes no `/dev/kvm` on any tier — so KVM-fast is impossible
there; that's why `win-batch` is TCG. Real KVM needs **bare metal**, which the
`hcloud`/tofu Cloud provider **cannot** provision:

- **Vultr Bare Metal** — hourly KVM, no minimum → genuinely on-demand. Best fit
  for ephemeral interactive Windows. Needs a Vultr provisioning path (the old
  vm-servers `providers/vultr/*` is the reference to re-express in uncloud terms).
- **Hetzner Robot (`ax41-nvme` ~€39/mo)** — KVM, but **30-day minimum + setup
  fee** → NOT cheaply ephemeral. Only worth it for sustained interactive use.

So: `win-batch` (Cloud TCG) ships first and covers batch. `win-kvm` is a later
addition gated on a bare-metal provisioning path; pick Vultr BM for on-demand.

## How a workload finds its node

Each ephemeral node class is its **own uncloud context** (separate tofu state +
`up`/`down`), so the Windows node's lifecycle is fully independent of the live
`cluster` node:

```
UNCLOUD_CONTEXT=hetzner       # cluster node (Moltis) — live
UNCLOUD_CONTEXT=win-batch     # Windows cloud node — up/down on demand
UNCLOUD_CONTEXT=dev           # Linux dev node — dev:up/dev:down on demand
UNCLOUD_CONTEXT=dev-win       # Windows dev node — dev:up:win/dev:down:win
```

RDP / viewer / SSH / GUI resolve the target node's IP from its context (tofu
output / `hcloud server ip <node>` / `uc machine ls`). Firewall: the cluster
firewall opens only 22/80/443/51820; each other class gets its own rule —
the Windows node opens `:3389` (RDP), the **dev** node opens the dev SSH port
(`dev_ssh_port`, default `2222`) for Remote-SSH/rsync into the container, both
restricted to `ssh_allowed_ips`. A **dev-win** node sets both flags, so it opens
RDP `:3389` and the dev SSH port.

> **Future:** RDP is plain TCP, so it's exposed via a raw `:3389@host` port + a
> dedicated firewall rule today. When uncloud ships **L4 TCP passthrough**
> ([discussion #280](https://github.com/psviderski/uncloud/discussions/280) /
> [issue #108](https://github.com/psviderski/uncloud/issues/108)), the windows
> recipe can route 3389 through the managed ingress instead — one place for ports.

## Build order

1. **win-batch** — ✅ DONE. `windows` var + `--context` workspaces; `win:up` →
   `win:deploy` → `win:rdp`/`win:viewer` → `win:snapshot` → `win:down`.
2. **Control plane** — ✅ DONE. RDP/viewer tasks (`win:rdp*`, `win:viewer`),
   cost ledger (`costs:show`), read-only web GUI (`gui:up`).
3. **win-kvm** — ✅ SCAFFOLDED (needs `VULTR_API_KEY` + a first live run to
   verify; Vultr BM is billable so untested here). Flow:

   ```bash
   # one-time: VULTR_API_KEY in keychain; VULTR_REGION/PLAN/OS_ID/SSH_KEY_ID in mise.local.toml
   mise run win-kvm:up        # create a Vultr Bare Metal node (uncloud cloud-init)
   mise run win-kvm:ip        # poll until it has an IP (~5-10 min)
   mise run win-kvm:init      # uc machine init → win-kvm context
   mise run win-kvm:deploy    # recipe windows-kvm (dockur + /dev/kvm)
   mise run win-kvm:rdp       # RDP in (native speed)
   mise run win-kvm:down      # destroy (no state preserved yet — see below)
   ```

   The `windows-kvm` recipe adds `/dev/kvm` (native virt). Any KVM Linux box
   works — `uc machine init <ip> --context win-kvm` then `recipe windows-kvm`;
   Vultr is just the automated provider. **Caveat:** Vultr BM has no native
   hot-snapshot — vm-servers preserved state via an R2-transit pipeline that is
   NOT yet ported, so `win-kvm:down` currently loses Windows state. For
   state-preserving on-demand Windows today, use **win-batch** (Hetzner snapshot).
   Porting the R2 snapshot path is the remaining win-kvm work.
