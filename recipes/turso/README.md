# Turso / libSQL (sqld)

Self-hosted SQLite-as-a-server — a **durable, authenticated** drop-in for
Cloudflare D1 that **any of our projects can consume**. Continuously backed up to
R2 (box is disposable), JWT-authenticated, multi-database, with a rehearsable DR
drill. Deploy it once; every project gets a robust SQLite DB.

```bash
mise run recipe:deploy turso          # deploy on the cluster (auth + backup -> R2)
mise run recipe:local turso    # locally (no auth/backup, ephemeral dev)
```

## Consume from another project (the easy path)

Three steps for any project to get its own robust SQLite database:

```bash
mise run turso:db:create myproject   # 1. create an isolated database
mise run turso:token                 # 2. get the client auth token
# 3. point a libSQL client at it (URL + token):
```

```js
// JS / TS  (@libsql/client)  — works on Workers, Node, Bun
import { createClient } from "@libsql/client";
const db = createClient({
  url: "http://sqld:8080",                     // in-cluster (overlay)
  authToken: process.env.TURSO_TOKEN,          // from `mise run turso:token`
});
await db.execute("create table if not exists t(x)");
```

```rust
// Rust (libsql crate)
let db = libsql::Builder::new_remote(
    "http://sqld:8080".into(),
    std::env::var("TURSO_TOKEN")?,
).build().await?;
```

Endpoints (both need the token):
- **In-cluster** apps → `http://sqld:8080`, select the database with the Host
  header `<myproject>.db`. Works today, fully isolated.
- **External** apps (Workers, etc.) → `https://db.<domain>` (TLS via the apex
  wildcard) reaches the **default** database. For per-project isolation over the
  public endpoint you need a `*.db.<domain>` wildcard cert (one Caddy/DNS step —
  see "Public multi-tenant" below); the apex `*.<domain>` wildcard doesn't cover
  the second-level `<proj>.db.<domain>`.

Want local-first reads? Use an **embedded replica** (`syncUrl` = the URL above) —
see "Read-scale" below. Every database is **automatically backed up to R2 and
covered by the weekly DR drill** — no per-project setup.

The contract: **URL + token + a database name.**

## Robustness: the box is disposable, R2 is the source of truth

A single SQLite box is a single point of data loss unless its write-ahead log is
shipped off-box. sqld's **bottomless** replication streams every WAL frame to
S3-compatible storage — here, your existing **R2** (creds derived from
`CLOUDFLARE_API_TOKEN`, exactly like the tofu state backend; no new secret). On
boot with an empty volume, sqld **restores automatically** from the latest
generation in the bucket.

Failure modes:

| Event | What happens |
|---|---|
| Container crash | uncloud restarts it; the local WAL replays |
| Volume lost | fresh sqld restores from R2 |
| **Whole box lost** | reprovision, deploy `turso`, it restores from R2 |

Verified end-to-end (against MinIO standing in for R2): wrote rows, **destroyed
the data volume entirely**, brought up a fresh node — data restored in ~17 ms,
all rows intact (log: `Finished database restoration … recovered=true`).

### Backup is mandatory on the cluster

`prepare.nu` refuses to deploy without R2 configured — robust means never running
prod without a backup target. Knobs:

- `TURSO_BUCKET` — R2 bucket for backups (default `vm-uncloud-turso`). **Create it
  first** in the Cloudflare dashboard, like `vm-uncloud-tfstate`.
- `TURSO_BACKUP=off` — deliberate opt-out (prints a loud warning). Used
  automatically by `recipe:local` for ephemeral dev.
- WAL checkpoints every 5 min (`SQLD_CHECKPOINT_INTERVAL_S`) bound how much recent
  data a catastrophic loss could cost.

## DR is code — rehearse recovery on demand

A backup you've never restored is a rumour. Recovery is built into the repo as
runnable commands (nushell over `bottomless-cli`, all **read-only on R2**):

```bash
mise run turso:dr:list      # what backup generations exist in R2
mise run turso:dr:verify    # WEEKLY DRILL: restore latest + integrity-check it
mise run turso:dr:restore   # pull a backup to a local sqld data dir (recovery)
```

- **`turso:dr:verify`** is the weekly drill. It restores the newest generation in
  a throwaway container and runs an integrity check, printing `✅ DR VERIFY
  PASSED` / `❌ FAILED` and **exiting non-zero on failure** — so it can gate a
  scheduled job or CI. Run it weekly (e.g. a cron/CI job invoking the task); if it
  ever fails, the backup is bad and you find out *before* you need it.
- **`turso:dr:restore`** does real recovery, including **point-in-time**:
  `mise run turso:dr:restore -- --utc-time 2026-06-24T12:00:00Z`. It writes a
  SQLite file you can inspect (`sqlite3 … 'PRAGMA integrity_check'`) or reload.

Verified against real R2: seeded a backup, `list`/`verify`/`restore` all green,
restored file passed `integrity_check` with the exact rows intact.

## Many databases — one server, unlimited isolated SQLite DBs

Namespaces are enabled, so this one sqld is a **fleet of D1-style databases**, not
just one. Each is fully isolated and gets its **own** independent R2 backup + DR.

```bash
mise run turso:db:create orders     # create a database
mise run turso:db:list              # list databases (from their R2 backups)
mise run turso:db:delete orders     # delete one (destructive)
```

- The `default` database answers at `http://sqld:8080` (backward-compatible — a
  single-DB app needs no namespaces knowledge).
- A named database `orders` is addressed by **Host subdomain**: a libSQL client
  pointed at `http://orders.db.<domain>` (Host `orders.…`) targets it. In-cluster,
  set the Host header against `sqld:8080`. Publicly, see "Public multi-tenant".
- Backups: each database lands under its own R2 prefix `ns-<db-id>:<name>`
  (db-id = `TURSO_DB_ID`, default `vmu-turso`). **`turso:dr:verify` checks every
  database automatically** and fails if any one is unrecoverable.

Verified against real R2: created `alpha` + `beta`, each backed up to its own
prefix, `dr:verify` passed both, `dr:restore beta` returned exactly `beta`'s rows.

The admin API (database create/delete) binds the overlay only — never public.

## Access + auth (libSQL-native JWT)

Two endpoints, both requiring a Bearer token:
- **Public**: `https://db.<domain>` — Caddy fronts it with the wildcard TLS cert
  (`x-ports`). For projects off the cluster (Workers, local dev, anything).
- **In-cluster**: `http://sqld:8080` on the overlay — for sibling containers.

`SQLD_AUTH_JWT_KEY` (an Ed25519 public key) makes every request require a JWT.
`prepare.nu` generates + persists the keypair (`auth.nu`, in a container since
macOS LibreSSL has no Ed25519) and `mise run turso:token` prints the client token.
Verified: no token / bad token → **401**, signed token → **200**.

> The admin API (database create/delete, port 9090) is **not** in `x-ports`, so it
> stays overlay-internal — never reachable from the public endpoint.

Rotating the keypair invalidates every client's token, so it's generated once and
kept stable in the keychain (like the other persisted secrets).

## Read-scale / multi-region (single-writer)

sqld is **single-writer**: one primary, many read replicas pulling its frame log.

- **Embedded replica** — an app holds a local SQLite file, reads hit it (zero
  network), writes forward to the primary, `.sync()` pulls new frames. Worth it
  when an app is far from the primary or wants offline-tolerant reads.
- **Server replica** — a second sqld node (`SQLD_NODE=replica`,
  `SQLD_PRIMARY_GRPC_URL=http://<primary>:5001`) serving a region's reads. This is
  the multi-region play across uncloud `location`s.

For a single-box deployment with sibling apps, skip replicas — `http://sqld:8080`
is already local-fast.

## Public multi-tenant (per-database public subdomains)

The default deploy exposes `https://db.<domain>` (the default database) — covered
by the apex `*.<domain>` wildcard cert. To give **each** database its own public
TLS subdomain (`<proj>.db.<domain>`), the cluster needs a **second-level wildcard
cert `*.db.<domain>`**, because `*.<domain>` only covers one label. One-time step:

1. tofu: add a `*.db.<domain>` (and `db.<domain>`) DNS record in Cloudflare.
2. Caddy: it gets the `*.db.<domain>` cert via the existing DNS-01 flow once it's
   asked to serve those hosts (add the route/x-ports for `*.db.${DOMAIN}`).

Until then, public consumers share the **default** database, and **per-database
isolation is available in-cluster today** (overlay + Host header). This is the one
piece that needs a live cluster to wire + verify.

## vs corrosion

Unrelated to the corrosion store uncloud runs internally. **corrosion** = the
cluster's own control-plane state (multi-writer CRDT gossip). **sqld** here = an
application database (single-writer, strongly consistent, R2-backed). Use turso
for app data; don't use corrosion as an app DB, and don't expect multi-master
writes from turso.
