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

## Recommendation

- **Now:** registry + secrets via the Bitwarden item/Send APIs (`scripts/registry.nu`,
  the dev-secrets flow) — works with stock OrangeVault, no admin worker.
- **Later:** when orangevault-admin lands auth + the config RPCs above, add a thin
  client (ConnectRPC is HTTP/JSON-friendly — `curl`/a small nu wrapper) and move
  account provisioning + structured registry/config there. Tracked here.
