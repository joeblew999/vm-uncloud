#!/usr/bin/env nu
# Config for the moq-relay recipe. recipe.nu runs this with DOMAIN in the env and
# merges the JSON it prints on stdout into the deploy env; stderr is human notes.
#
# Emits MOQ_RELAY_CONFIG — the full moq-relay TOML — which compose.yaml writes to
# a file in the container at start (uncloud can't bind-mount host files). SCAFFOLD
# defaults: self-signed TLS + anonymous auth. Harden before production (see
# README.md): a real cert for moq.<domain> and token auth via moq-token-cli.

def main [] {
  let domain = ($env.DOMAIN? | default "")
  let host = (if ($domain | is-empty) { "moq.localhost" } else { $"moq.($domain)" })

  # moq-relay TOML. QUIC on UDP:4443, HTTP/WS on TCP:4443, self-signed cert for
  # the host, anonymous access. Built line-by-line so it stays readable.
  let config = ([
    "[log]"
    'level = "info"'
    ""
    "[server]"
    "# QUIC / WebTransport listener (UDP)."
    'listen = "[::]:4443"'
    "# SCAFFOLD: self-signed cert for the host. Clients use the certificate.sha256"
    "# fingerprint (served on the HTTP port). Production: supply a real cert."
    $'tls.generate = ["($host)"]'
    ""
    "[web.http]"
    "# HTTP + WebSocket + certificate.sha256 (TCP)."
    'listen = "[::]:4443"'
    ""
    "[auth]"
    "# SCAFFOLD ONLY — anonymous access to everything. Production: token auth."
    'public = ""'
  ] | str join "\n")

  print -e $"moq-relay: SCAFFOLD config for ($host) — self-signed TLS + anonymous auth. HARDEN before production."
  print -e "moq-relay: requires a node firewall rule for UDP:4443 + TCP:4443 (cluster opens only 22/80/443/51820)."
  print -e $"moq-relay: QUIC/WebTransport at https://($host):4443 once the firewall + cert are sorted."

  { HOST: $host, MOQ_RELAY_CONFIG: $config } | to json
}
