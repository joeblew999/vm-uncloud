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
| **build-win** | Vultr Bare Metal (KVM) | Windows | dockur **KVM** | snapshot-resume | builds on `win-kvm` |
| **build-mac** | ⚠️ no Vultr Mac — needs Apple HW (Mac mini / MacStadium) | macOS | native | TBD | **open question** |

Reuses existing machinery: the `win-kvm` recipe, `scripts/vultr-snapshot.nu`
(R2-transit snapshots), `r2/`, and `scripts/state-remote.nu`.

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
  - Vultr **Mac** availability — does it exist? If not, macOS = Mac mini / MacStadium (per the no-cross-compile rule). **VERIFY.**
  - **Persistent vs ephemeral** runners: persistent keeps the cache (the whole point) but bills continuously and is a security risk on public repos. Lean persistent + on-demand wake, gated to trusted refs.
  - **Cache strategy**: native persistent `~/.cargo` + per-repo `target/` on the desktop disk (simplest, biggest win) vs sccache.
- **Phase 1 — `build-linux` (proof)**: provision a Linux desktop; install runner agent + mise + rustup; `mise run mise:global`; register with labels; snapshot → R2. Flip **jackdaw**'s `os-matrix` to the self-hosted linux runner; prove the 2nd build is fast (warm cache).
- **Phase 2 — `build-win` on `win-kvm`**: bake runner + mise + rustup into the `windows-kvm` recipe; register; prove the jackdaw **Windows** build (the one currently failing on GitHub). Validates `vultr-snapshot.nu` on a real run (it's an unverified port today).
- **Phase 3 — `build-mac`**: gated on a Mac-hardware path (Phase 0).
- **Phase 4 — snapshot/restore lifecycle**: `builder:up` / `builder:down` / `builder:snapshot` via `vultr-snapshot.nu` + `r2`; scheduled cache-warm refresh.
- **Phase 5 — reusable-mise-ci integration**: consuming repos set `os-matrix` to runner labels; keep GitHub runners as fallback when a desktop is down. Consider a `free-disk` / runner-selection input on `reusable-mise-ci.yml`.
- **Phase 6 — cost + security**: feed runner uptime into the cost ledger (`state/costs.jsonl`, `costs:show`, GUI); on-demand wake vs always-on. **SECURITY:** self-hosted runners on a **public** repo run untrusted PR code — restrict to our own branches / private repos / ephemeral runners. jackdaw is a public fork → do NOT run untrusted PRs on a persistent builder.

## Risks / open questions

- **Vultr Mac** — likely unavailable; macOS may have to stay on GitHub or move to dedicated Apple hardware.
- **Security** — public-repo self-hosted runners + untrusted PRs = RCE. Gate hard.
- **Billing vs latency** — persistent (always paying, instant) vs snapshot-resume (cheap idle, boot latency).
- `vultr-snapshot.nu` is an **unverified port** — Phase 2's first real `win-kvm` run is its validation.

## First consumer

**jackdaw** (Bevy, ~43 GB `target/`, currently slow/failing on GitHub-hosted
runners) is the forcing function and the first repo to flip its `os-matrix` to a
vm-uncloud builder. Its mise CI is already shaped for this (see
`joeblew999/jackdaw` `joeblew999` branch: `.github/workflows/mise.yaml`).
