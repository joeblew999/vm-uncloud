# rauthy recipe — TODO

## Route Rauthy's outbound email through Cloudflare

Rauthy sends transactional email — email-address verification, password-reset
links, passwordless magic links, MFA-reset, and admin notifications. By default
it speaks **SMTP** (`SMTP_URL` / `SMTP_USERNAME` / `SMTP_PASSWORD` / `SMTP_FROM`,
plus `SMTP_DANGER_INSECURE` for local). Without a working mail path those flows
silently break (a user can't verify their address or reset a password).

We want this to go through our **Cloudflare email** path, not a third-party SMTP
provider. The gap: **Rauthy emits SMTP; Cloudflare sends via Workers/API**, so a
bridge is needed.

### Open decision — how to bridge SMTP → Cloudflare
- **A. SMTP-relay shim → CF.** Stand up a tiny SMTP server that accepts Rauthy's
  mail and forwards it via the CF send path. Point `SMTP_URL` at it. Most
  drop-in for Rauthy (no Rauthy changes), but adds a relay component.
- **B. Reuse existing CF email infra.** We already have:
  - `cf_email_worker` + `nu_plugin_email` (http-nu **email-native** branch — CF
    Email Service, beta/paid ~$0.35/1K)
  - `saasmail` (CF Workers unified inbox; issue #111 `/api/inbound` + MCP/webhook)
  - the Moltis multi-channel gateway on Hetzner
  The relay in (A) should forward into one of these rather than a new sender.
- **C. Patch Rauthy** to call an HTTP send endpoint instead of SMTP — upstream
  change / fork; heavier, last resort.

Leaning **A → into the existing CF send path (B)**: keep Rauthy stock (SMTP),
put the CF-specific logic in the shim. Verify deliverability end-to-end (a real
password-reset email lands) before calling it done.

### Acceptance
- `SMTP_*` configured in the recipe (secrets via prepare.nu/fnox).
- A Rauthy-triggered email (e.g. password reset) is delivered via Cloudflare.
- Works for both the cluster deploy and `recipe:local` (local can stay
  `SMTP_DANGER_INSECURE` / a catch-all, prod uses the CF path).

Related: [[project_saasmail]], [[project_http_nu_email_native]].
