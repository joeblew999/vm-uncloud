# Upstream uncloud — issues & friction

Bugs/friction hit running [uncloud](https://github.com/psviderski/uncloud) in
this repo, with repros, impact, and our workarounds. Tracked here so the
workarounds in our code have a paper trail and we can drop them when fixed
upstream. Encountered on `uc` **0.19.0**.

| File | Issue | Upstream | Workaround in repo |
|---|---|---|---|
| [env-newline.md](env-newline.md) | `${VAR}` env injection appends a trailing `\n` in the container → breaks API tokens (Caddy DNS-01) | **[#393](https://github.com/psviderski/uncloud/issues/393)** | `caddy/compose.yaml` trims CR/LF at container start |
| [machine-init-tty.md](machine-init-tty.md) | `uc machine init` readiness spinner needs a TTY → fails headless/CI | **#386** (existing; commented) | `scripts/up.nu` + finish deploys manually |

See also `CLAUDE.md` and the `feedback_vm_uncloud_gotchas` memory.
