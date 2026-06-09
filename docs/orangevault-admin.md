# orangevault-admin as the config/registry control plane (future)

[orangevault-admin](https://github.com/joeblew999/orangevault-admin) is a
ConnectRPC `AdminService` worker over **the same D1** as OrangeVault — privileged,
structured operations the user-facing Bitwarden API doesn't expose. That's the
right *shape* for the "Russian doll" config/registry plane (program against
OrangeVault directly instead of driving the Bitwarden client API item-by-item).

## Current surface (from the proto)

`AdminService`: `Healthz`, `ListUsers`, `GetUser`, `RotateSecurityStamp`,
`ListOrganizations`, `ListUserMemberships`, `DeleteUser`. So today it's **user/org
administration** — read + a couple of lifecycle ops.

**Auth:** bearer **macaroon** (`libmacaroon`, `MACAROON_ROOT_KEY`) — but the code
says *"TODO: gate every RPC on a macaroon"* / *"no auth middleware yet"*. So it is
**not network-safe to expose yet**.

## Why we don't use it for the registry yet

The live-systems registry ([REGISTRY.md](REGISTRY.md)) writes Bitwarden **items**
(`vmu/<ctx>/<svc>` with the URL in `uri`) via the stock `bw` CLI against the
dedicated account. That works against **unmodified OrangeVault** today and is
readable by any fnox `bitwarden` provider — no admin worker required.

orangevault-admin would be the better control plane once it:

1. **ships the macaroon auth middleware** (so it's safe to reach over the network);
2. **exposes the ops we'd actually want**, which it doesn't yet — e.g.
   - `CreateAccount` → auto-provision the **dedicated dev/CI account** (today that's
     a manual web-UI register + API key, because bw/rbw can't register);
   - org/collection management → scope dev/CI secrets + registry entries cleanly;
   - structured **registry list/query** (bulk, filter) instead of per-item
     Bitwarden calls;
   - Send management → mint/rotate/expire the capability-URL "public" tokens
     (see [DEVCONTAINERS.md](DEVCONTAINERS.md) Sends) programmatically.

## Does it need a compiled binary on GitHub for mise to include?

**No — and it doesn't ship one today.** Facts from the repo:

- `Cargo.toml` is `crate-type = ["cdylib", "rlib"]` (a **WASM Worker library**) — no
  `[[bin]]`, no client CLI crate. There's **no `.github/` release workflow** (only
  `web/buf.gen.yaml` for TS codegen). The only client is the **TypeScript React
  admin UI** served as Worker assets.
- The admin **server is a Cloudflare Worker** — it deploys to **Cloudflare, not
  GitHub**. Only a separate *client* would ever be a GitHub release artifact.
- It's **ConnectRPC = JSON over HTTP**, so any repo can call it **without a binary**:
  `POST /orangevault_admin.v1.AdminService/<Method>` with a JSON body,
  `Content-Type: application/json`, and the bearer macaroon header — i.e. `curl` or
  nushell `http post`. That's the idiomatic, zero-dependency client for vm-uncloud.

A mise-installable CLI binary is a **nice-to-have, not a need**. To provide one (so
repos `mise use github:joeblew999/orangevault-admin`), the **admin repo** would add:
a `[[bin]]` client crate (reusing the connectrpc-generated types) **and** a GitHub
Releases workflow emitting per-OS/arch assets (mise's `github:`/`ubi:` backends
fetch release assets). That work lives in orangevault-admin — **outside this repo's
scope** — so it can't be done from here.

Either path is gated on the **macaroon auth middleware** landing first: the RPC
isn't network-safe yet, so no client should drive it over the network until then.

## Recommendation

- **Now:** registry + secrets via the Bitwarden item/Send APIs (`scripts/registry.nu`,
  the dev-secrets flow) — works with stock OrangeVault, no admin worker.
- **Later:** when orangevault-admin lands auth + the config RPCs above, add a thin
  client (ConnectRPC is HTTP/JSON-friendly — `curl`/a small nu wrapper) and move
  account provisioning + structured registry/config there. Tracked here.
