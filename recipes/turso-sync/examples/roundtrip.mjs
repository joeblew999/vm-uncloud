// Offline-first sync round-trip against a self-hosted turso-sync server.
// PROVEN against tursodb 0.6.1 + @tursodatabase/sync 0.6.1: client A writes to a
// LOCAL file and pushes; independent client B pulls and sees the row.
//
// This doubles as the CONSUMER example — this is how an offline-first app talks to
// the turso-sync recipe. It is intentionally standalone (its own node deps) so the
// vm-uncloud repo keeps its Rust+nushell toolchain; run it out-of-band:
//
//   mise run recipe:local turso-sync                 # start the server (:8080)
//   cd recipes/turso-sync/examples
//   npm install                                      # @tursodatabase/sync
//   SYNC_URL=http://localhost:8080 node roundtrip.mjs
//
// Against a deployed server: SYNC_URL=https://db-sync.<domain> (+ an auth proxy).
import { connect } from "@tursodatabase/sync";

const URL = process.env.SYNC_URL ?? "http://localhost:8080";
const val = `written-${Date.now()}`;

// Client A — the offline-first pattern: writes hit a LOCAL SQLite file at file
// speed (no network), then push() ships them to the server when connected.
const a = await connect({ path: "a.db", url: URL, clientName: "A" });
await a.connect();
await a.exec("create table if not exists notes(id integer primary key, body text)");
await a.exec(`insert into notes(body) values ('${val}')`);
await a.push();
console.log("A: wrote locally + pushed");

// Client B — a separate device/file. pull() brings A's change down.
const b = await connect({ path: "b.db", url: URL, clientName: "B" });
await b.connect();
await b.pull();
const rows = await (await b.prepare("select body from notes")).all();
await a.close();
await b.close();

if (!rows.some((r) => r.body === val)) {
  console.error("FAIL: B did not see A's row:", JSON.stringify(rows));
  process.exit(1);
}
console.log("PASS: A wrote offline + pushed, B pulled and saw it");
