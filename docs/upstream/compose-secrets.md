# Native compose secrets — revisit the OrangeVault dev-container flow when it lands

Upstream: **[PR #385](https://github.com/psviderski/uncloud/pull/385) "feat: add
secrets"** (in progress), with **[#75](https://github.com/psviderski/uncloud/issues/75)**
(compose secrets from files) and **[#76](https://github.com/psviderski/uncloud/issues/76)**
(secrets with custom drivers). Related: **[#43](https://github.com/psviderski/uncloud/issues/43)**
(compose configs, done). Not a bug — a feature that will let us **simplify** our
secrets design.

## Summary

uncloud is adding first-class compose `secrets` (mounted at `/run/secrets`), and
the maintainer has discussed resolving secrets **client-side** from external
providers (1Password, Vault, **Bitwarden**, AWS Secrets Manager, …) and injecting
them into containers at deploy time. Bitwarden is exactly what OrangeVault speaks,
so this overlaps directly with what we built for dev-container secrets.

## What we do today (and why)

The dev-container secrets flow (`recipes/dev-linux/` + `tasks/dev.toml`, see
[`../DEVCONTAINERS.md`](../DEVCONTAINERS.md#secrets-via-orangevault)) resolves
secrets **inside the container**, because uncloud has no secret injection yet:

- the recipe injects a dedicated dev/CI OrangeVault account's bootstrap creds
  (`OV_*`: server, email, API key, **master password**) as container env;
- `ov-bootstrap.sh` runs `bw login --apikey` + `bw unlock` at start;
- `uncloud:dev:*` runs the remote task under `fnox exec` so its `[providers.orangevault]`
  secrets resolve.

The cost of doing it in-container: the dev/CI account's **unlock creds live on the
node** (mitigated by the dedicated account + only persisting the revocable
`BW_SESSION`), and we bake `bw`/`fnox` into the image.

## What to revisit when #385 lands

Move resolution **client-side** and let uncloud inject only the resolved values:

1. On the operator/dev machine, `fnox` (already configured against OrangeVault)
   resolves the needed secrets, and uncloud injects them as **secret files
   (`/run/secrets`) or env** into the dev container.
2. Then we can **drop** from `recipes/dev-linux/`:
   - `ov-bootstrap.sh` and the `OV_*` env injection (no API key / **no master
     password on the node**),
   - baking `bw` into the image (and `fnox`, if nothing else needs it),
   - the `~/.config/ov/session` persistence.
3. `tasks/dev.toml` may no longer need the `fnox exec` wrapper — secrets arrive as
   env/files already.
4. **Re-evaluate the security model**: with only resolved values injected (not the
   vault-unlock creds), the "dedicated dev/CI account" requirement softens — a
   personal vault could be safe again, since the node never holds unlock creds.
5. If #76 (custom drivers) ships a Bitwarden-speaking driver, point it straight at
   OrangeVault — potentially **no `fnox`/`bw` in the container at all**.

## Status

**Don't act yet** — PR #385 is in progress. When it merges (and we bump `uc`),
revisit `recipes/dev-linux/{Dockerfile,compose.yaml,entrypoint.sh,ov-bootstrap.sh,prepare.nu}`
and the `tasks/dev.toml` `fnox exec` wrapping against the shipped API.
