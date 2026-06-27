# rauthy recipe

Rauthy (OpenID Connect IdP) as a reusable vm-uncloud recipe — the AuthN plane.
Runs on the cluster (`mise run recipe:deploy rauthy`) or locally (`mise run
recipe:local rauthy`, → http://localhost:8080).

## Declarative per-project bootstrap

Each project that authenticates against this Rauthy declares its OIDC
**clients** (and optional **roles**/**groups**) in [`bootstrap.nuon`](bootstrap.nuon)
— the AuthN counterpart to a project's Cedar policy files for AuthZ. On an empty
production DB Rauthy imports them on first boot.

```nuon
{
  clients: [
    { id: "worker-client", name: "…", flows: ["password","client_credentials"],
      scopes: ["openid","profile","groups"], redirect_uris: ["https://…/callback"] }
  ]
  roles: ["superuser"]
  groups: ["eng"]
}
```

You never write a secret here. `prepare.nu` **generates** a stable 64-char secret
per client (exactly 64 — Rauthy validates with `constant_time_eq_64`; longer
stores but never matches), persists it in the fnox keychain
(`VMU_RAUTHY_CLIENT_<id>`), and prints it once. Consumers read it from the
keychain — the same cross-repo secret contract as every other vm-uncloud secret.

How it flows: `prepare.nu` (reads `bootstrap.nuon`, gens secrets, emits
`BOOTSTRAP_CLIENTS/ROLES/GROUPS` JSON env) → `rauthy-init` writes them into the
shared `cfg` volume's `BOOTSTRAP_DIR` → Rauthy imports on first boot.

> Future cleanup: Rauthy [PR #1599](https://github.com/sebadob/rauthy/pull/1599)
> adds **generated** bootstrap secrets + `rauthy bootstrap get`/`purge` — once it
> ships in a release, Rauthy generates the secret itself and we just extract it,
> dropping our generate-and-inject step.

## Why the recipe looks the way it does (boot-verified)

- The image is **distroless** (no shell) and **panics without `/app/config.toml`**
  — env only *overrides* that file. uncloud can't bind-mount a host file, so
  `rauthy-init` seeds an (empty) config.toml + the bootstrap dir into a shared
  volume, and rauthy reads them via `serve -c /cfg/config.toml`.
- Mandatory or it crash-loops: `TRUSTED_PROXIES` (with `PROXY_MODE=true`),
  `ENC_KEYS`+`ENC_KEY_ACTIVE`, `HQL_SECRET_RAFT`/`_API`, `RP_ID`/`RP_ORIGIN`/`RP_NAME`.
- Behind TLS-terminating Caddy: `LISTEN_SCHEME=http` + `PROXY_MODE=true` +
  `PUB_URL=id.<domain>` (host only). Issuer = `https://id.<domain>/auth/v1/`
  (path suffix); verify it's **https** on first boot.
- `client_credentials` tokens have `sub: null` → use the **password grant** for a
  user token carrying `sub` + roles.

## Email → Cloudflare (Rauthy stays stock)

Rauthy sends transactional mail (verification, password reset, …) over SMTP;
Cloudflare sends via HTTP. The recipe bridges them WITHOUT touching Rauthy:

```
Rauthy ──SMTP──► bridge (smtp2http) ──POST──► saasmail /api/rauthy-inbound ──► CF Email
(SMTP_URL=bridge)  internal net only         (the CF-send code, in the email repo)
```

- **`bridge`** = `alash3al/smtp2http`, a tiny SMTP→webhook forwarder, a service in
  this compose. Listens `:1025` on the internal network only (never exposed).
  Rauthy points at it via `SMTP_URL=bridge` + `SMTP_DANGER_INSECURE=true` (plain,
  internal). **Verified locally:** it forwards mail as `application/x-www-form-
  urlencoded` (`addresses[from]`, `addresses[to]`, `subject`, `body[text]`,
  `body[html]`).
- **The webhook** = `bootstrap.nuon`'s `email.webhook` → your CF email worker's
  inbound endpoint. The matching handler lives in **saasmail**
  (`/api/rauthy-inbound`, branch `feat/rauthy-inbound`) — it parses that form and
  sends via Cloudflare Email. Rauthy never changes; CF-send code stays in the
  email repo.
- **Auth:** smtp2http can't add headers, so put a shared secret in the webhook
  URL as `?key=<secret>` (`email.webhook`) and set saasmail's
  `RAUTHY_WEBHOOK_SECRET` to match.

Not yet end-to-end live: triggering a real Rauthy email needs PoW (reset) or the
admin API (create-user), and the CF send needs a domain onboarded at CF Email —
both deploy-time. The bridge hop + the saasmail handler are individually verified.

## TODO

See [TODO.md](TODO.md).
