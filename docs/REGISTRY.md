# Live-systems registry — OrangeVault as service discovery

When vm-uncloud runs something on Hetzner, its public URL becomes **known in
OrangeVault**, so other systems can discover and use it by name. vm-uncloud and the
stuff it runs are then self-describing — a registry layered on the same
OrangeVault you already use for secrets (the "Russian doll": the vault holds both
the secrets *and* the map of what's live).

## How it works

On deploy, `recipe.nu` records the service's URL as a Bitwarden **login item** in
OrangeVault:

- **name**: `vmu/<context>/<service>` (e.g. `vmu/hetzner/moltis`, `vmu/dev/dev-linux`)
- **uri**: the live URL (`https://moltis.<domain>`)
- **notes**: JSON `{context, service, kind, url, updated}`

Because the URL lives in the item's `uri` field, **any repo whose fnox has the
orangevault provider resolves it by name** — no bespoke discovery protocol:

```toml
# a consumer project's fnox.toml
[providers.orangevault]
type = "bitwarden"
[secrets]
MOLTIS_URL = { provider = "orangevault", value = "vmu/hetzner/moltis/uri" }
```

## Two layers: Cloudflare DNS + OrangeVault

vm-uncloud already manages **Cloudflare DNS** (tofu creates `*.<domain>`,
`dev.<domain>`, `windows.<domain>`), so discovery is naturally two complementary
layers — no new infrastructure:

- **DNS = the address layer.** A service published on `<service>.<domain>` already
  *resolves* (wildcard A record) and is routed by Caddy. So the URL is
  deterministic from the recipe's host — public, zero-auth, already there.
- **OrangeVault = the catalog + secrets layer.** It records *which* services exist,
  their metadata (`kind`, `updated`), any non-public endpoints, and the secrets to
  use them — queryable by name via fnox, gated by the dedicated account.

So the registry entry's `uri` is simply the DNS name vm-uncloud already created;
OrangeVault adds the queryable catalog and the auth/secrets that DNS can't. A
consumer resolves the address from either (DNS for public, OrangeVault for the
catalog/private bits).

## Enabling it

Writing uses the `bw` CLI against the **dedicated dev/CI account** (same creds as
the dev-container secrets — `ORANGEVAULT_DEV_*` in the keychain; URL from
`$ORANGEVAULT_DEV_DOMAIN`). So `mise run dev:secrets:set` is the prerequisite.

Test it live first (manual), then turn on auto-publish:

```bash
# manual — verify the bw item CRUD against your live vault
mise run registry:publish -- --context hetzner --service moltis --url https://moltis.amplifycms.com
mise run registry:list
mise run registry:remove  -- --context hetzner --service moltis

# auto — every recipe deploy publishes its URL
#   mise.local.toml:  [env]\n  VMU_REGISTRY = "1"
mise run recipe:deploy moltis        # now also registers vmu/hetzner/moltis -> https://moltis.<domain>
```

It is **best-effort and self-guarding**: with no `bw` / no creds, or `VMU_REGISTRY`
unset, it no-ops — it can never break a deploy.

## Status

**EXPERIMENTAL — verify on first use.** The `bw` item create/edit/delete in
`scripts/registry.nu` hasn't been exercised against a live vault here; run the
manual `registry:*` tasks once to confirm before setting `VMU_REGISTRY=1`. The
read side (fnox `…/uri`) is standard Bitwarden field access.

## Config plane — orangevault-admin (future)

For richer registry/config operations than the Bitwarden item API exposes
(bulk listing, structured queries, lifecycle), the
[orangevault-admin](https://github.com/joeblew999/orangevault-admin) ConnectRPC
`AdminService` (over the same D1) is the natural control plane — see
[orangevault-admin.md](orangevault-admin.md).
