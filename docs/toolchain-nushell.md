# Note: nushell is pinned (and the `job spawn` flag fixed)

**Status: resolved.**

## What happened

`mise run ci` parses every `nu` script. One file failed —
`connect/rdp-wait.nu` used `job spawn --description "rdp-wait"`, but current
nushell's flag is **`--tag`** (`--description` isn't a thing on `job spawn`). So it
failed the CI parse on *any* recent `nu`, not just an old one — it was a renamed
flag, not a version-too-old problem. Compounding it, nushell wasn't pinned in
`mise.toml`, so `mise install` didn't provide a known `nu` at all.

## The fixes

1. `connect/rdp-wait.nu`: `job spawn --description` → `job spawn --tag` (same
   meaning — a cosmetic job label).
2. `mise.toml [tools]`: pin `"aqua:nushell/nushell" = "0.111.0"` so `mise install`
   provides the `nu` the scripts + CI parse run on.

Verified: with nushell 0.111.0 + the flag fix, `mise run ci` passes (`✓ CI passed`).

## If you bump nushell later

`nu`'s `job` subsystem is experimental and flags can churn. If a future bump
breaks the CI parse again, check the changed command's `help` (e.g. `help job
spawn`) for renamed flags rather than assuming the version is too old.
