# Dev Containers — remote dev on the recipes

Build and test your project on a remote box that **matches the deploy target**,
while your repo stays on your Mac. Useful when local ≠ prod: compiling Rust for
`linux/amd64` from an Apple-silicon Mac, or needing real Windows to test a
Windows build. The remote dev environment is **just another uncloud recipe** —
no parallel lifecycle, same `up`/`recipe`/`down` idiom as everything else.

There are two recipes and two ways in:

| | `dev-linux` | `dev-windows` (EXPERIMENTAL) |
|---|---|---|
| Image | Dev Containers base + mise + sshd | dockur/windows + `/oem` (mise, git, OpenSSH) |
| Node class | `dev` (tofu `dev = true`) | `dev-win` (`windows = true` **and** `dev = true`) |
| Primary entry | VS Code Remote-SSH / `ssh` / rsync | RDP (`win:rdp`) + `\\host.lan\Data` |
| Toolchain | each project's `mise.toml` | each project's `mise.toml` (in-guest) |

> Infrastructure recipes (caddy, imaginary, wordpress, moltis) are **not** dev
> targets — they're services. Dev Containers is only `dev-linux` / `dev-windows`.

## Add to any repo (TL;DR)

Any repo with a `mise.toml` at its root opts in with **one include** — nothing to
vendor (mise pulls just that file, like `cliff.toml`):

```toml
# <project>/mise.toml
[task_config]
includes = ["git::https://github.com/joeblew999/vm-uncloud.git//tasks/dev.toml?ref=<tag-or-branch>"]
```

```toml
# <project>/mise.local.toml   (per developer, not committed)
[env]
DEV_HOST = "dev.amplifycms.com"   # the dev node — or its IP (mise run dev:ip)
```

Then `mise run uncloud:dev:build` (sync + the project's `build` on the node), or
the assumption-free `mise run uncloud:dev:exec -- <any-task>`. Toolchains come from
the project's own `mise.toml`, so this works for any language. The named wrappers
(`uncloud:dev:build` / `…:test` / `…:release`) assume tasks called
`build`/`test`/`release`; `uncloud:dev:exec -- <task>` makes no such assumption.
The tasks are namespaced with **`uncloud:`** so they can't clash with the
project's own tasks — the operator tasks below (`dev:up`/`dev:deploy`/…) are
plain `dev:*` because they live only in the vm-uncloud repo, never included.

## Two paths to the same node

1. **Recipe path (idiomatic).** The dev environment is the `dev-linux` recipe,
   deployed and torn down with `mise run dev:*`. You reach it over SSH (Remote-SSH
   or terminal) and rsync your repo in. This honors *"everything is an uncloud
   recipe"* and gives cost-disciplined, teardownable nodes.
2. **Portable devcontainer path.** A standard `.devcontainer/devcontainer.json`
   in your project + the Dev Containers CLI, pointed at the node's Docker over SSH
   (`DOCKER_HOST=ssh://root@<node>`). This is the literal *Reopen in Container*
   experience and also works locally / in Codespaces — but it drives the node's
   Docker directly, outside uncloud's deploy/lifecycle. Use it as the escape hatch.

Both end up compiling on the same remote box. Start with the recipe path.

---

## Operator: stand up a dev node (in this repo)

```bash
cp tofu/dev.tfvars.example tofu/dev.tfvars     # one-time; edit domain/zone/ssh, tighten ssh_allowed_ips
mise run dev:up                                # provision the Linux dev node (dev context)
mise run dev:deploy                            # build + deploy the dev-linux recipe onto it
mise run dev:ssh:wait                          # block until sshd is reachable
mise run dev:ip                                # the node IP (or use dev.<domain>)
# ... developers work (below) ...
mise run dev:down                              # destroy when idle (workspace is on the dev's Mac)
```

The `dev` tofu node class mirrors `win-batch`: its own context/workspace + tfvars,
its own teardownable Hetzner node. It opens **only** the dev SSH port
(`dev_ssh_port`, default `2222`, restricted to `ssh_allowed_ips`), points
`dev.<domain>` at the node, and claims no wildcard (it serves SSH, not web).

`prepare.nu` authorizes **your** SSH public key inside the container
(`DEV_SSH_PUBKEY`, or the first of `~/.ssh/id_ed25519.pub` / `id_rsa.pub` /
`gedw99_hetzner.pub`). To authorize a teammate, set `DEV_SSH_PUBKEY` to their key
and re-run `dev:deploy`.

Connect helpers (operator-side, resolve the node by name):

```bash
mise run dev:code     # VS Code Remote-SSH into /workspace (writes a ~/.ssh/config alias)
mise run dev:ssh      # interactive shell in the container
mise run dev:status   # describe the node
```

---

## Developer: build your project on the node

Your project repo already has `mise` with `build` / `docker` / `release` tasks.
Wire in the shared `dev:*` namespace — mise pulls just `tasks/dev.toml`, the same
way it pulls `cliff.toml`:

```toml
# your-project/mise.toml
[task_config]
includes = ["git::https://github.com/joeblew999/vm-uncloud.git//tasks/dev.toml?ref=<tag-or-branch>"]
```

```toml
# your-project/mise.local.toml   (per developer, NOT committed)
[env]
DEV_HOST = "dev.amplifycms.com"   # or the node IP from `mise run dev:ip`
# optional: DEV_PORT (2222) · DEV_USER (vscode) · DEV_REMOTE_ROOT (/workspace)
#           DEV_PROJECT (repo dir name) · DEV_SSH_KEY (~/.ssh/...)
```

Then the loop:

```bash
mise run uncloud:dev:sync             # rsync the repo to the node (honors .gitignore, keeps .git)
mise run uncloud:dev:exec -- build    # run THIS project's `mise run build` on the node
mise run uncloud:dev:build            # sync + build in one shot
mise run uncloud:dev:test             # sync + test
mise run uncloud:dev:release          # sync + the project's release task (binary + docker + GitHub)
mise run uncloud:dev:code             # open VS Code Remote-SSH at the synced repo
mise run uncloud:dev:shell            # interactive shell on the node, in the repo
```

Toolchains are **not** baked into the image — the first `mise run` installs
exactly what your `mise.toml` pins (Rust version, etc.). Build artifacts and the
mise cache live in the `dev_workspace` / `dev_mise` volumes, so they stay warm
across redeploys (but go away with `dev:down` — the source of truth is your Mac).

The project's `mise run docker` task works because the container mounts the
node's Docker socket (grants Docker access — same trade-off as the moltis recipe).

### Portable path (Reopen in Container)

Copy [`templates/dev/devcontainer.json`](../templates/dev/devcontainer.json) to
your project's `.devcontainer/devcontainer.json` (or `mise generate devcontainer
--write` and merge), add the CLI, and point it at the node:

```toml
# your-project/mise.toml → [tools]
"devcontainer-cli" = "latest"
```

```bash
mise run uncloud:dev:container    # DOCKER_HOST=ssh://root@$DEV_HOST devcontainer up
```

The same `.devcontainer/` opens locally in VS Code's *Dev Containers* extension
and in GitHub Codespaces with no changes.

---

## Windows (EXPERIMENTAL)

`dev-windows` is the `windows` recipe plus first-boot dev provisioning
(`recipes/dev-windows/oem/install.bat`: mise + git, best-effort OpenSSH). It runs
on a node that is both a Windows node and a dev node:

```bash
cp tofu/dev-win.tfvars.example tofu/dev-win.tfvars   # windows = true AND dev = true
mise run dev:up:win
mise run dev:deploy:win
# The win:* RDP tasks resolve WIN_NODE (default win-batch-1) — point them here:
export WIN_NODE=dev-win-1                             # or set it in mise.local.toml
mise run win:rdp:wait && mise run win:rdp            # RDP in (user Docker / pass admin)
```

Supported loop today: get the repo into Windows via `\\host.lan\Data` (the
`devwin_shared` volume — rsync to the node's volume or copy over RDP), open a
Windows terminal, and run `mise run build`. **Remote-SSH into the guest is not yet
verified** — it needs dockur to forward the published `:22` to the guest, and the
key delivered at `\\host.lan\Data\dev\authorized_keys`. Confirm on a live node
before relying on it; until then RDP + the shared folder is the path.

For native-speed Windows (TCG is ~10× slower) use the bare-metal `win-kvm` class.

---

## Operations (CI / Claude Code / headless)

The loop is mise tasks, so an agent (or CI) drives it the same way a person does —
`mise tasks` to discover, `mise run …` to execute. What matters is which tasks are
non-interactive:

**Agent-safe (non-interactive):**
operator (vm-uncloud repo) — `dev:up`, `dev:deploy`, `dev:ip`, `dev:status`,
`dev:ssh:wait`, `dev:down`, `dev:down:win`; consumer (project repo) —
`uncloud:dev:sync`, `uncloud:dev:exec -- <task>`, `uncloud:dev:build`,
`uncloud:dev:test`, `uncloud:dev:release`. (`dev:up`/`dev:deploy` are headless —
the uncloud fork dropped the PTY requirement; teardown is auto-confirmed, below.)

**Human-only (an agent should skip):**
operator — `dev:code` (VS Code Remote-SSH) / `dev:ssh` (interactive TTY);
consumer — `uncloud:dev:code` / `uncloud:dev:shell`; and the Windows `win:rdp` /
`win:viewer`.

**Teardown is headless by design.** Unlike the cluster/win teardown (which prompts
for the node name), `dev:down` / `dev:down:win` pass `--yes` — a dev node is
reproducible (its only state, the synced repo, lives on the dev's Mac), so
operations / CI / Claude Code can take it down non-interactively and re-create it
with `dev:up` + `dev:deploy`. (`dev:down:win` does **not** snapshot the Windows
guest — use the `win:*` flow if you need to preserve guest state.)

**Secrets in a headless session.** Operator tasks (`dev:up`/`dev:deploy`/`dev:down`)
need `HCLOUD_TOKEN` + `CLOUDFLARE_API_TOKEN` — from the `fnox` keychain locally, or
the plain env vars in CI/cloud (where there's no keychain). The project loop
(`uncloud:dev:sync`/`uncloud:dev:exec`/…) only needs `DEV_HOST` set and an SSH key the agent can
read (`DEV_SSH_KEY`, or a default `~/.ssh` key).

## Security notes

- **Lock the firewall.** `ssh_allowed_ips` gates node `:22`, the dev SSH port, and
  RDP. Default is open — set it to your IP(s) in the tfvars.
- **Keys only.** The dev-linux sshd disables password auth; only the injected
  public key gets in.
- **Docker socket.** `dev-linux` (and moltis) mount the node's Docker socket so
  in-container `docker`/`mise run docker` works — that's full Docker access on the
  node. Deploy dev nodes you trust the developers on.
- **Teardownable + cheap.** `dev:down` destroys the node; nothing of value lives
  only there (your repo is on your Mac). Bring it back with `dev:up` + `dev:deploy`.
