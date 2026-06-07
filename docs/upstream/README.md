# Upstream uncloud — issues & friction

Bugs/friction hit running [uncloud](https://github.com/psviderski/uncloud) in
this repo, with repros, impact, and our workarounds. Tracked here so the
workarounds in our code have a paper trail and we can drop them when fixed
upstream. Encountered on `uc` **0.19.0**.

| File | Issue | Upstream | Workaround in repo |
|---|---|---|---|
| [env-newline.md](env-newline.md) | `${VAR}` env injection appends a trailing `\n` in the container → breaks API tokens (Caddy DNS-01) | **[#393](https://github.com/psviderski/uncloud/issues/393)** | `caddy/compose.yaml` trims CR/LF at container start |
| [machine-init-tty.md](machine-init-tty.md) | `uc machine init` readiness spinner needs a TTY → fails headless/CI | **[#386](https://github.com/psviderski/uncloud/issues/386)** (answered empirically) | `up.nu`/`vultr-init.nu` PTY-wrap init in `script` |

## Watching — enhancements that would let us simplify

Not bugs; upstream features that would replace a workaround/limitation here.

| Upstream | What it'd let us drop |
|---|---|
| [PR #385](https://github.com/psviderski/uncloud/pull/385) — compose `secrets` (`/run/secrets`) | inject the CF DNS-01 token + `MOLTIS_TOKEN` as secret **files** instead of `${VAR}` env → likely sidesteps the [#393](https://github.com/psviderski/uncloud/issues/393) trailing-`\n`, so we drop the `tr -d '\r\n'` trim in `caddy/compose.yaml` (caveat: confirm the secret *file* itself has no trailing `\n`). Commented. |
| [disc #280](https://github.com/psviderski/uncloud/discussions/280) / [#108](https://github.com/psviderski/uncloud/issues/108) — L4 TCP/UDP passthrough | RDP `:3389` via the managed ingress instead of raw `@host` + a manual firewall rule (commented our use case) |
| [#369](https://github.com/psviderski/uncloud/issues/369) — `uc undeploy` / "app" concept | per-recipe teardown without whole-node `tofu destroy` (commented our recipes-as-apps use case) |

See also `CLAUDE.md` and the `feedback_vm_uncloud_gotchas` memory.
