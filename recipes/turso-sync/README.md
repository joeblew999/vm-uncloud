# turso-sync — the new Turso engine's sync server (offline-first)

The **"good sync stuff"**: the new Turso database engine (`tursodatabase/turso`, the
Rust rewrite) does **bidirectional, offline-first sync** — an app writes to a
**local** SQLite file at file speed while offline, then **push/pulls** against this
server when connected. This recipe self-hosts that server (`tursodb --sync-server`)
so the sync target is *your box*, not Turso Cloud.

```bash
mise run recipe:local turso-sync       # build + run locally (:8080)
mise run turso-sync:smoke              # prove the sync protocol works
mise run recipe:local turso-sync --down
```

Proven end-to-end against `tursodb` 0.6.1: the server serves both protocol
endpoints — `POST /v2/pipeline` (SQL over HTTP) and `POST /pull-updates` (the
protobuf WAL page-updates an offline client pulls since its last revision).

## `turso-sync` vs `turso` — pick the right one

They are **different engines for different jobs**. Most projects want `turso`.

| | **`turso`** (recipe: `recipes/turso`) | **`turso-sync`** (this recipe) |
|---|---|---|
| Engine | libSQL / **sqld** (SQLite fork) | new **Turso** engine (Rust rewrite) |
| Role | central **D1-style server** | **offline-first sync** server |
| Client | libSQL client over the network | embedded local file + `@tursodatabase/sync` push/pull |
| Auth | ✅ native Ed25519 JWT | ❌ none native (front a proxy only if exposed publicly) |
| TLS | ✅ via Caddy | via Caddy (no native) |
| Off-box backup | ✅ bottomless (streams every frame) | ✅ snapshot → R2 (periodic, not streaming) |
| Multi-DB | ✅ namespaces | single file |
| Maturity | production | **BETA** |

**Choose `turso`** for a robust central database (the default). **Choose
`turso-sync`** only when you specifically need offline-first, local-write-then-sync
apps (mobile/desktop/edge that must work disconnected).

## How it's packaged

Upstream publishes **no server image** for the new engine — only prebuilt CLI
binaries. So we don't build from source: [`Dockerfile`](Dockerfile) drops the
**pinned upstream `tursodb` binary** into a slim image (multi-arch via
`TARGETARCH`: amd64 for the cluster, arm64 for the cax boxes). Bump `TURSO_VERSION`
in the Dockerfile **and** `compose.yaml` together — the engine is BETA and the
on-disk / sync formats can shift between releases.

## Consume it (offline-first client) — PROVEN

An app embeds the new Turso engine, opens a **local** file, and syncs to this
server: `connect({ path, url })` then `exec` offline + `push()` / `pull()`. A
worked, runnable round-trip lives in [`examples/roundtrip.mjs`](examples/roundtrip.mjs)
— **verified**: client A writes to its local file and pushes; an independent client
B pulls and sees the row.

```bash
mise run recipe:local turso-sync
cd recipes/turso-sync/examples && npm install
SYNC_URL=http://localhost:8080 node roundtrip.mjs      # → PASS
```

Point `url` at `https://db-sync.<domain>` for a deployed server (behind an auth
proxy). The example is standalone (its own node deps) so the repo keeps its
Rust+nushell toolchain.

## Durability — snapshot → R2 (PROVEN against MinIO)

The new engine has no bottomless. Its sync server keeps a growing WAL (checkpoint
disabled), so durability is an **online consistent snapshot**: `VACUUM INTO` over
`/v2/pipeline` yields a clean single-file copy while the server runs, shipped to
R2. Restore = pull it back as the DB file. Same "R2 is the source of truth, the
box is disposable" story as the sqld recipe — a snapshot *cadence* bounds the loss
window instead of streaming.

```bash
mise run turso-sync:backup           # snapshot -> R2
mise run turso-sync:backup:verify    # snapshot -> download -> integrity_check (drill)
mise run turso-sync:restore          # pull latest snapshot to a local file
```

S3 target defaults to R2 (creds derived from `CLOUDFLARE_API_TOKEN`, like the sqld
recipe). Override `TURSO_SYNC_ENDPOINT` + `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
for a self-host/MinIO target. **Verified** end-to-end against local MinIO:
`backup:verify` snapshots the live server, uploads, re-downloads, and passes
`pragma integrity_check`. Schedule `backup:verify` like the sqld weekly DR drill.

> Cadence, not streaming: run `turso-sync:backup` on a schedule; data written since
> the last snapshot is lost on a box failure. For zero-loss durability use the
> `turso` (sqld) recipe, whose bottomless streams every WAL frame.

## Known gaps (BETA — read before deploying)

This is a deliberately **minimal** server today. Before any real use:

- **No auth.** The sync server has no native authentication. Do **not** expose it
  publicly unguarded — put an auth proxy (or keep it overlay-internal) in front.
- **No native TLS.** Caddy terminates TLS via the wildcard cert (the `x-ports`
  `/https` route), same as every other recipe.
- **Backup is snapshot-cadence, not streaming.** Durability is now wired
  (`turso-sync:backup*`, verified against MinIO) but it's periodic `VACUUM INTO` →
  R2, so writes since the last snapshot are lost on a box failure. For zero-loss,
  use the `turso`/sqld recipe (bottomless streams every frame).
- **Single-writer, one request at a time** (reference-server concurrency model).
- **BETA engine** — pin the version and re-verify `turso-sync:smoke` on every bump.

## Roadmap (to make it production-grade)

1. ~~**Client round-trip proof**~~ — ✅ done ([`examples/roundtrip.mjs`](examples/roundtrip.mjs)).
2. ~~**Durability**~~ — ✅ snapshot → R2, drill verified against MinIO
   (`turso-sync:backup:verify`). Follow-up: schedule it; tune snapshot cadence.
3. **Auth** — a front proxy (the sync server has none of its own). Needed before
   any public exposure.
4. **Publish the image** — build+push `tursodb` to our registry (the `.github`
   cliff:release fork-image path) so uncloud can deploy it without a local build.
5. **Cluster deploy** — wire `db-sync.<domain>` + the snapshot job on a live box
   (both cluster-gated, like the sqld recipe's public-subdomain item).
