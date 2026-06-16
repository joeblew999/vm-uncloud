# GitHub CI integration — self-hosted build runners

Plan for [#5](https://github.com/joeblew999/vm-uncloud/issues/5). Companion to
[PLACEMENT.md](./PLACEMENT.md) — this adds **build-runner** node classes.

## Why

GitHub-hosted runners are slow and disk-starved (~14 GB). Jackdaw's Bevy build
alone produces a ~43 GB `target/` — it can't be cached on a GitHub runner, so
every run is cold. On a **persistent desktop** where the git checkout and the
rust build cache are always present, the same build goes from **~1 h → ~5 min**
(per #5). No docker inside the desktop — build natively on the desktop OS.

The build itself doesn't change: every repo already uses the shared mise CI
(`reusable-mise-ci.yml` + `[task_config].includes` from `.github`). "git clone →
mise takes over" is identical on a GitHub runner or one of our desktops — so
onboarding a repo = pointing its `os-matrix` at our runner labels.

## Node classes (extends PLACEMENT.md)

| Class | Provider / SKU | OS | Virt | Lifecycle | Status |
|---|---|---|---|---|---|
| **build-linux** | Vultr BM (hourly) or Hetzner Cloud `cpx*` | Linux | native | snapshot-resume | proposed |
| **build-win** | Vultr Bare Metal (KVM) | Windows | `dockurr/windows` **KVM** | snapshot-resume | builds on `win-kvm` |
| **build-mac** | Vultr Bare Metal (KVM) | macOS | `dockurr/macos` **KVM** | snapshot-resume | **recipe added** (`recipes/macos-kvm/`) — needs a live KVM node + runner layer |

> macOS via **`dockurr/macos`** — the same dockur/KVM container trick as
> `dockurr/windows` (the `windows` recipe), so **no Apple hardware needed**, just
> a KVM host (Vultr BM). ⚠️ Caveat: running macOS on non-Apple hardware is against
> Apple's licensing/EULA — fine for personal/experimental use; flag it before
> relying on it in shared/public CI.

Reuses existing machinery: the `win-kvm` recipe, `scripts/vultr-snapshot.nu`
(R2-transit snapshots), `r2/`, and `scripts/state-remote.nu`.

**Desktop engines (dockur org):**
- **`dockurr/windows`** (52k★) — Windows in a KVM container. Already used by the `windows` recipe.
- **`dockurr/macos`** (20k★) — macOS the same way (`build-mac`). EULA caveat above.
- **`dockurr/qemu`** — the generic KVM/QEMU base under both; boot *any* OS image. The natural engine for **booting a prepared qcow2 from R2** (snapshot-resume), or an isolated Linux VM if we ever want one.
- **`dockurr/windows-arm`** (2.2k★) — Windows-on-ARM, if we run ARM hosts (`cax*` / Apple Silicon).
- **Linux needs none of these** — the host is already Linux, so `build-linux` runs natively on the box (no container-VM wrapper).

## Foundation: Vultr Bare Metal (on-demand KVM)

The KVM runners (**build-win**, **build-mac**) need `/dev/kvm`, which means bare
metal. The economics decide the provider:

- Hetzner **Cloud** — no `/dev/kvm` (TCG only, ~10× slow). ✗
- Hetzner **Robot** — real KVM but **30-day minimum + setup fee** → can't teardown at will. ✗
- **Vultr Bare Metal** — **hourly KVM, no minimum** → spin up → build → snapshot to R2 → destroy. Pay only for hours used. ✓ **This is why we don't need a standing Hetzner dedicated box.**

(**build-linux** needs no KVM — Linux runs native, so it can go on a cheap
Hetzner Cloud node or the same Vultr box.)

**Current state — scaffolded, never run live** (`win-kvm` class):
`scripts/vultr-{up,init,down,snapshot}.nu` + `win-kvm:*` tasks
(`up → ip → init → deploy → rdp → down`), provisioned via `vultr-cli` (not tofu);
`VULTR_API_KEY` wired in `fnox.toml` (keychain).

**To light it up (prerequisite for build-win/build-mac):**
1. **`mise run win-kvm:onboard`** — HIL onboarding: checks every prerequisite and
   guides you through getting/setting each token (`VULTR_API_KEY`, R2 creds) and
   picking the non-secret config (region/plan/ssh-key, enumerated once the key
   works). Idempotent — re-run until all ✓.
2. One live `win-kvm:up → init → deploy → down` run — verifies provisioning + the headless PTY init.
3. **Verify + wire `vultr-snapshot.nu`** (R2 transit) into teardown — it's an unverified port and `vultr-down.nu` does NOT preserve state today. This is the piece that makes teardown-at-will keep the **warm rust cache** (the 1h→5min win).

## How a runner works

1. Desktop boots from an **R2 snapshot** pre-baked with: the GitHub Actions
   runner agent (labels `self-hosted,<os>,builder`), **mise**, **rustup**, and a
   **warm `~/.cargo` + per-repo `target/` cache**.
2. The consuming repo's workflow (already the shared `reusable-mise-ci`) sets
   `os-matrix` to the self-hosted labels.
3. On a job: git fetch (checkout persists) → `mise run <task>` → mise installs
   any missing tools (cached) → build against the warm cache → minutes.
4. Snapshot back to R2 periodically so the cache stays warm across spins.

## Phases / TODO

- **Phase 0 — decisions** (resolve before building):
  - macOS path: **`dockurr/macos`** on a KVM host (same as `dockurr/windows`) — no Apple HW needed. Confirm the licensing posture before shared/public CI use.
  - **Persistent vs ephemeral** runners: persistent keeps the cache (the whole point) but bills continuously and is a security risk on public repos. Lean persistent + on-demand wake, gated to trusted refs.
  - **Cache strategy**: native persistent `~/.cargo` + per-repo `target/` on the desktop disk (simplest, biggest win) vs sccache.
- **Phase 1 — `build-linux` (proof)**: provision a Linux desktop; install runner agent + mise + rustup; `mise run mise:global`; register with labels; snapshot → R2. Flip **jackdaw**'s `os-matrix` to the self-hosted linux runner; prove the 2nd build is fast (warm cache).
- **Phase 2 — `build-win` on `win-kvm`**: bake runner + mise + rustup into the `windows-kvm` recipe; register; prove the jackdaw **Windows** build (the one currently failing on GitHub). Validates `vultr-snapshot.nu` on a real run (it's an unverified port today).
- **Phase 3 — `build-mac`**: add a `macos` recipe using **`dockurr/macos`** (same dockur/KVM pattern as the `windows` recipe), on a KVM host. Register `[self-hosted, macos, builder]`; prove the jackdaw macOS build. Confirm the macOS-on-non-Apple-HW licensing posture first.
- **Phase 4 — snapshot/restore lifecycle**: `builder:up` / `builder:down` / `builder:snapshot` via `vultr-snapshot.nu` + `r2`; scheduled cache-warm refresh.
- **Phase 5 — reusable-mise-ci integration**: consuming repos set `os-matrix` to runner labels; keep GitHub runners as fallback when a desktop is down. Consider a `free-disk` / runner-selection input on `reusable-mise-ci.yml`.
- **Phase 6 — cost + security**: feed runner uptime into the cost ledger (`state/prices-*.jsonl`, `prices:show`, GUI); on-demand wake vs always-on. **SECURITY:** self-hosted runners on a **public** repo run untrusted PR code — restrict to our own branches / private repos / ephemeral runners. jackdaw is a public fork → do NOT run untrusted PRs on a persistent builder.

## Risks / open questions

- **macOS via `dockurr/macos`** — works without Apple HW (KVM container, like dockur/windows), BUT macOS on non-Apple hardware violates Apple's EULA. OK for personal/experimental; decide before shared/public CI relies on it.
- **Security** — public-repo self-hosted runners + untrusted PRs = RCE. Gate hard.
- **Billing vs latency** — persistent (always paying, instant) vs snapshot-resume (cheap idle, boot latency).
- `vultr-snapshot.nu` is an **unverified port** — Phase 2's first real `win-kvm` run is its validation.

## First consumer

**jackdaw** (Bevy, ~43 GB `target/`, currently slow/failing on GitHub-hosted
runners) is the forcing function and the first repo to flip its `os-matrix` to a
vm-uncloud builder. Its mise CI is already shaped for this (see
`joeblew999/jackdaw` `joeblew999` branch: `.github/workflows/mise.yaml`).
