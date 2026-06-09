# Note: nushell version (toolchain) — pin it if `mise run ci` parse fails

**Status:** latent, not currently blocking CI. Captured during the Dev Containers
work so it can be fixed deliberately later.

## What's going on

nushell is **not pinned** in `mise.toml` `[tools]`. The repo's `nu` scripts use
newer-nushell features, so they only parse on a recent enough nushell:

- `connect/rdp-wait.nu` uses `job spawn --description` / `job send` / `job recv`
  (the experimental `job` subsystem) — **needs nushell ≥ 0.109** (0.108 fails).
- Several scripts use `get -o` (the `--optional` short flag), also recent.

Because there's no pin, `mise run ci` uses whatever `nu` the environment provides:
- CI (`jdx/mise-action`) and an up-to-date Mac → fine, `nu` is new enough.
- An older `nu` (e.g. a fetched 0.108) → `mise run ci` reports a single parse
  failure on `connect/rdp-wait.nu` ("`job spawn` doesn't have flag `description`").
  This is a **toolchain-version mismatch, not a code bug** — the file is correct
  on a current nushell.

## The fix (when you want to do it)

Pin nushell in `mise.toml` `[tools]` to a known-good version so `mise install`
gives everyone the same `nu` and CI is reproducible. Note the registry short name
is ambiguous (`nu` also matches numbat/nuclei/nuclio) — use the explicit backend:

```toml
[tools]
# ... existing tools ...
"aqua:nushell/nushell" = "0.109.0"   # or the current stable; must be >= 0.109
```

Verify with `mise install` then `mise run ci`. Pick the latest stable unless a
later nushell breaks one of the scripts.

### Alternative

If you'd rather not depend on the experimental `job` API, refactor
`connect/rdp-wait.nu` to a plain `loop { sleep ...; if (port-open) { break } }`
(like `connect/ssh-wait.nu` already does) — then the scripts parse on older
nushell too and pinning is less critical.
