# moq-relay — Media over QUIC

[moq.dev](https://moq.dev) relay: forwards live media subscriptions from
publishers to subscribers over **QUIC / WebTransport**, caching and
deduplicating along the way. Real-time latency at scale.

```bash
mise run recipe:deploy moq
```

Runs the **official prebuilt image** `moqdev/moq-relay` (multi-arch amd64 +
**arm64**, so it runs on `cax` ARM nodes too) — no fork, no build, consistent
with the run-upstream-containers policy.

## ⚠ Status: SCAFFOLD — not yet deploy-verified

The compose + `prepare.nu` are a good-faith starting point. moq-relay isn't a
plain HTTP service, so three things must be sorted on the first real deploy:

| # | item | scaffold default | production |
|---|---|---|---|
| 1 | **UDP ingress + firewall** | raw `4443/udp@host` + `4443/tcp@host` | the cluster firewall only opens `22/80/443/51820` — **add a `4443` UDP+TCP rule** (in `tofu/`, like the windows `:3389` rule) or moq is unreachable. QUIC is **not** HTTP, so the wildcard-cert Caddy ingress can't front it. |
| 2 | **TLS** | self-signed (`tls.generate`) — browsers need the `certificate.sha256` fingerprint served on the TCP port | a **real cert for `moq.<domain>`** (mount one, or terminate WebTransport with a proper cert). |
| 3 | **Auth** | anonymous (`[auth] public = ""`) | **token auth** via `moqdev/moq-token-cli` — generate a root key, issue tokens, set `[auth]` in the config. |

## How it's wired

- moq-relay takes one argument: a TOML config file. uncloud can't bind-mount
  host files, so `prepare.nu` emits the whole config as `MOQ_RELAY_CONFIG` and
  `compose.yaml`'s entrypoint writes it to `/tmp/relay.toml` before exec'ing the
  relay. **Verify this injection on first deploy** (`uc logs` for the relay).
- QUIC/WebTransport on **UDP:4443**; HTTP + WebSocket fallback + the
  `certificate.sha256` on **TCP:4443**.
- Config reference: moq's [`demo/relay/localhost.toml`](https://github.com/moq-dev/moq/blob/main/demo/relay/localhost.toml)
  and [doc.moq.dev](https://doc.moq.dev).

## To take it to production

1. Add the `4443` UDP+TCP firewall rule to the node class in `tofu/`.
2. Swap the self-signed cert for a real `moq.<domain>` cert.
3. Stand up token auth (`moqdev/moq-token-cli`) and set `[auth]` in `prepare.nu`.
4. Pin/bump the image tag (`0.12.13` today; `latest` is multi-arch).

## Clients

This recipe is the **relay** (server). For mobile clients, **Software Mansion's
[moq-kit](https://github.com/software-mansion-labs/moq-kit)** gives native
**Swift (iOS 16+) and Kotlin (Android API 29+)** SDKs to connect to a relay,
discover broadcasts, publish camera/mic/screen tracks, and play streams. It's
built on `moq-ffi` (UniFFI bindings) from the same `moq-dev/moq` core, so it
speaks the same protocol — point its endpoint at `moq.<domain>:4443`. Distributed
via Swift Package Manager + Maven Central (Apache-2.0).

Web/CLI clients come from `moq-dev/moq` itself (`moqdev/moq-cli`, the JS
WebTransport client).
