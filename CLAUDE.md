# Context for Claude Code — vm-uncloud

The **single home for all our Hetzner deployments**, via [uncloud](https://github.com/psviderski/uncloud).
One tool, one provisioning idiom (tofu + `fnox` keychain secrets), one cost
ledger. Supersedes the old `vm-servers` repo (don't add a parallel lifecycle —
everything is an uncloud recipe or a thin mise task over uncloud/tofu/hcloud).

## Two workloads, two node classes (see `docs/PLACEMENT.md`)

- **cluster** — always-on Hetzner Cloud node (`cpx22`), runs many containers as
  recipes (Moltis, WordPress, …), each on a `*.<domain>` subdomain via one
  wildcard DNS-01 Caddy. LIVE at `amplifycms.com` (Moltis = `moltis.amplifycms.com`).
- **win-batch** — dedicated, teardownable `cpx42` Windows node (dockur/windows),
  its OWN tofu workspace + uncloud context (`--context win-batch`). RDP `:3389`.
  Cost discipline: `win:up` → `win:deploy` → work → `win:down` (snapshot then
  destroy). TCG (`KVM=N`) — Hetzner Cloud has no `/dev/kvm`; KVM-fast = bare
  metal (Vultr/Robot), a future class.

## Layout

- `scripts/*.nu` — tofu+uncloud lifecycle (`cluster-up`/`cluster-down`/`recipe-deploy`/`cluster-status`). All
  take `--context` to target a node class (default = the cluster; workspace
  "default" + `terraform.tfvars`). `def main`-style (CI parse-checks via `source`).
- `recipes/<name>/` — `compose.yaml` (+ optional `prepare.nu`) per service:
  moltis, windows, wordpress, imaginary. `mise run recipe:deploy <name> [-- --context X]`.
- `connect/*.nu` — RDP/viewer client helpers (run-style; CI parse-checks via `nu-check`).
- `gui/server/serve.nu` — one http-nu + Datastar closure = the read-only web
  status board. `pitchfork.toml` supervises `gui` + `xs`. `mise run gui:up`.
- `tofu/` — `windows` var gates the win node class (RDP firewall, `windows.<domain>`,
  no wildcard). `state/prices-*.jsonl` = price model (`mise run prices:show`).

## Gotchas (don't relitigate — see [[feedback_vm_uncloud_gotchas]])

1. **uncloud appends `\n` to every injected env value.** Harmless except for
   exact-match values — it broke the CF token for Caddy DNS-01. Trim CR/LF in the
   consuming container (`caddy/compose.yaml` wraps the command with `tr -d`).
2. **`uc machine init`'s readiness spinner needs a TTY** (bubbletea opens
   `/dev/tty`). `cluster-up.nu`/`vultr-init.nu` auto-wrap init/add in a PTY
   (`script -q /dev/null`, OS-dispatched), so `mise run cluster:up` works headless.
   (Verified on uncloud#386: `| cat` does NOT help, a PTY does.) Drop the wrapper
   if uncloud ships a `--plain`/`--no-tui` path.
3. **Moltis** needs `MOLTIS_NO_TLS=true` with `MOLTIS_BEHIND_PROXY=true`.
4. `fnox set` ALWAYS with `-p keychain` (else plaintext into `fnox.toml`).
   `tofu` reads `HCLOUD_TOKEN`/`CLOUDFLARE_API_TOKEN` from env via `fnox exec` —
   verify infra with `fnox exec -- hcloud ...`, not bare `hcloud`.
5. Run `cluster:up`/`cluster:down` from a REAL terminal (TTY). `mise run ci` before committing.
6. **uncloud is `uc` since v0.20** (binary renamed `uncloud`→`uc`; daemon stays
   `uncloudd`). On a machine's FIRST boot the daemon pulls the Corrosion **Docker
   image**, and that pull can exceed systemd's start timeout → `uc machine
   init/add` fails once, the daemon auto-restarts and comes up (image cached).
   It's intermittent — `cluster-up.nu` + `arm.nu` wrap init/add in `with-pty-retry`
   (PTY + 3× retry). Verified live on 0.20 (2026-06-27). gRPC proxy format changed
   in 0.20, so CLI + all machines must share a major — upgrade with no cluster up.

## Don't

- Don't run Windows on the cluster node (cpx22 too small) or co-locate it — it's
  its own teardownable node.
- Don't copy vm-servers' bespoke lifecycle in — desktop virt is the `windows` recipe.
- Don't `git commit`/`push` without explicit user approval.
