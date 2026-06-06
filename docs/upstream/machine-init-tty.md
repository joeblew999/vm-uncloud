# `uc machine init` requires a TTY (headless / CI)

Upstream: **already filed** — psviderski/uncloud **#386** ("uc machine init
requires a TTY in non-interactive shells (`could not open TTY`)", open
2026-06-03). We added a [corroborating comment](https://github.com/psviderski/uncloud/issues/386#issuecomment-4637370769)
rather than duplicate. `uc` 0.19.0.

## What we saw

`mise run up` (which ends with `uc machine init root@<ip> … -y`) fails in a
non-interactive shell at the post-init readiness step:

```
Error: wait for cluster to be ready: bubbletea: error opening TTY:
bubbletea: could not open TTY: open /dev/tty: device not configured
```

## Notable detail (worth adding to #386)

The failure is **only** the readiness spinner. By the time it errors:

- the remote daemon is installed and running,
- the local context **is** created (`uc context ls` shows it, with the machine
  registered), and
- `uc machine ls` reports the machine `Up`.

So the cluster is actually functional — only the TUI wait blows up. Recovery is
to skip `init` and run the remaining (headless-safe) steps by hand: `uc machine
ls` to confirm, then `uc deploy …` for ingress + recipes.

## Ask

A non-interactive path for the readiness wait — e.g. honor `-y`/`--no-tui`/
`CI=1`/no-TTY by polling without bubbletea — so `uc machine init` completes in
CI and automation.

## Verified (2026-06-06, answered on #386)

Tested on a throwaway node (uc 0.19.0, non-interactive shell, no controlling TTY):

- **`uc machine init root@<ip> --no-dns -y | cat`** → cluster initialises, then
  `Error: wait for cluster to be ready: … could not open TTY: open /dev/tty:
  device not configured` (exit 1). **`| cat` does NOT help** — it redirects
  stdout, but the spinner opens `/dev/tty` directly.
- **`script -q /dev/null uc machine init root@<ip> --no-dns -y`** (give it a PTY)
  → `Cluster is ready.` (exit 0). **Works.**

## Fix in this repo (auto)

`scripts/up.nu` now wraps `uc machine init`/`add` in a PTY (`with-pty` →
`script -q /dev/null …` on macOS/BSD, `script -qec "…" /dev/null` on Linux), and
`scripts/vultr-init.nu` does the same for win-kvm. So `mise run up` completes
headlessly — no manual finish needed. Drop the wrapper if/when uncloud ships a
`--plain`/`--no-tui` path (#386).
