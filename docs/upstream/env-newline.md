# Injected env values get a trailing newline in the container

Upstream: **psviderski/uncloud#393**. `uc` 0.19.0.

## Summary

When a compose service uses `environment: { KEY: ${VAR} }`, the value that lands
in the container has a trailing newline (`\n`) appended — even though the source
env var has none. This silently breaks any consumer that does exact-string
matching, notably API tokens: the trailing `\n` corrupts an `Authorization`
header and the remote rejects the token as invalid.

## Environment

- `uc` version: **0.19.0**
- Client: macOS (arm64); single Hetzner Cloud node, uncloud-managed Caddy.

## Reproduce

`compose.yaml`:

```yaml
services:
  probe:
    image: alpine
    command: ["sh", "-c", "printenv FOO | od -c; sleep 3600"]
    environment:
      FOO: ${FOO}
```

```bash
FOO=hello uc deploy -f compose.yaml -y
uc logs probe      # or: docker exec <ctr> printenv FOO | od -c
```

## Expected vs actual

- **Expected:** `FOO` in the container is exactly `hello` (5 bytes).
- **Actual:** `FOO` is `hello\n` (6 bytes) — a trailing newline is appended.

The source value is clean: `printf %s "$FOO" | od -c` shows no newline; only the
in-container value has `\n`. Observed identically for an inline value
(`FOO=hello`) and for a value injected from a secrets manager — so the `\n` is
added during uncloud's `${VAR}` substitution / env injection, not by the source.

## Impact

Breaks exact-match values. Concretely: a `caddybuilds/caddy-cloudflare` ingress
reading `{env.CLOUDFLARE_API_TOKEN}` for the ACME **DNS-01** challenge fails with
`API token … appears invalid; … not wrapped in braces nor quotes`, so no wildcard
cert is ever issued and `:443` serves nothing — despite the token being valid
(`/user/tokens/verify` → active) and able to edit DNS.

## Workaround

Strip CR/LF in the container before use:

```yaml
command:
  - sh
  - -c
  - |
    export CLOUDFLARE_API_TOKEN="$$(printf '%s' "$$CLOUDFLARE_API_TOKEN" | tr -d '\r\n')"
    exec caddy run -c /config/Caddyfile
```

(`$$` escapes compose interpolation so the container shell expands it.)
