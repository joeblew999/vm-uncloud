# state — what's on what servers

`log.jsonl` is the durable, append-only ledger of cluster lifecycle events. It answers *"what did I deploy, where, and when?"* even after a cluster is torn down — the thing `uc machine ls` can't tell you once the box is gone.

Three layers of truth, smallest-lived first:

| Source | Truth about | Lifetime |
|--------|-------------|----------|
| `uc machine ls` / `uc ls` | live machines + running services | while the cluster exists |
| `tofu/*.tfstate` | exactly which cloud resources exist | while infra exists |
| **`state/log.jsonl`** (this) | full history of up / deploy / down | forever (git) |

Events are written automatically by `up.nu`, `recipe.nu`, and `down.nu` via `log.nu` (typed subcommands). Each line is one JSON object with an auto `ts`:

```jsonc
{"event":"up","cluster":"hetzner","ips":"167.233.52.142","server_type":"cpx22","location":"fsn1","fqdns":"wordpress.amplifycms.net","ts":"2026-06-03T08:30:00+0000"}
{"event":"deploy","cluster":"hetzner","service":"wordpress-mariadb","host":"wordpress.amplifycms.net","ts":"..."}
{"event":"down","cluster":"hetzner","ts":"..."}
```

`mise run status` prints the live state plus the tail of this ledger. Commit it (`git add state/log.jsonl`) so the inventory is shared and versioned.
