# Placement — which node class runs which workload

One repo, one tool (uncloud). But not one node: workloads differ in size, burst,
and whether they need real virtualization (KVM). This is the map. Pricing is in
`state/costs.jsonl` (`mise run costs:show`).

## Node classes

| Class | Provider / SKU | Virt | Lifecycle | For |
|---|---|---|---|---|
| **cluster** | Hetzner Cloud `cpx22` (2/4) | container | **always-on** | Moltis + light web containers. **LIVE** (`amplifycms.com`). |
| **win-batch** | Hetzner Cloud `cpx42` (8/16) | dockur **TCG** (`KVM=N`) | **ephemeral**: up → `recipe windows` → snapshot → down | Windows batch / unattended (Revit RBP). ~10× slower than KVM, but cheap & hourly. **NEXT TO BUILD.** |
| **win-kvm** | Vultr Bare Metal (hourly) or Hetzner Robot `ax*` | dockur **KVM** (`/dev/kvm`) | ephemeral (Vultr) / 30-day-min (Robot) | Interactive Windows where TCG is too slow. **FUTURE** — see caveat. |

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
```

RDP / viewer / GUI resolve the target node's IP from its context (tofu output /
`hcloud server ip <node>` / `uc machine ls`). Firewall: the Windows node opens
`:3389` (RDP, restrict to your IP) — the cluster firewall opens only
22/80/443/51820, so the win node gets its own rule.

## Build order

1. **win-batch provisioning** — a parameterized node flavor (size + context) so
   `up`/`down` can stand a dedicated `cpx42` Windows node with a `:3389` rule,
   independent of the cluster. Then `recipe windows` onto it.
2. **Port the control plane** onto that node (as it works): RDP mise tasks
   (`vm:rdp`, `vm:rdp:wait`, `vm:viewer`), the cost ledger (done), then the web
   GUI (adapted to drive `up`/`down`/`recipe`/`status` instead of the old
   bespoke lifecycle).
3. **win-kvm** — Vultr Bare Metal path for on-demand KVM (later).
