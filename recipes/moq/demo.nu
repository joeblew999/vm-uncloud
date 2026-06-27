#!/usr/bin/env nu
# Local moq demo — the whole Media-over-QUIC stack on your box, orchestrated here
# in nushell. Server side runs as the upstream CONTAINERS (the run-containers
# policy): the relay is `moqdev/moq-relay`, the publisher is `moqdev/moq-cli`. The
# web UI is moq's own `demo/web` Vite app — moq publishes no web image, so it runs
# under bun (vite, no node). The CLUSTER deploy is the sibling compose.yaml +
# prepare.nu; THIS is the local dev/demo path.
#
#   mise run moq:demo -- up      # relay (docker) + web UI -> http://localhost:5173/publish.html
#   mise run moq:demo -- pub     # publish Big Buck Bunny into the relay (needs ffmpeg)
#   mise run moq:demo -- status
#   mise run moq:demo -- down
#
# Needs: docker (OrbStack) + bun (mise tool). pub also needs ffmpeg.

const RELAY = "moq-relay"
const WEB = "moq-web"             # pitchfork daemon name for the Vite server
const SRC = ".src/moq"            # upstream clone (gitignored, like the recipe catalog)
const PORT = "5173"
const RELAY_URL = "http://localhost:4443"

def ensure-src [] {
  if not ($SRC | path exists) {
    print $"==> cloning moq into ($SRC)"
    ^git clone --depth 1 https://github.com/moq-dev/moq $SRC
  }
}

def relay-up []: nothing -> bool {
  (^docker ps --format "{{.Names}}" | lines | any {|n| $n == $RELAY })
}

def "main up" [] {
  ensure-src

  # 1. Relay container: QUIC on UDP:4443 + HTTP/WS on TCP:4443, self-signed for
  #    localhost (the demo config ships anonymous auth).
  if (relay-up) {
    print "==> relay already running"
  } else {
    ^docker rm -f $RELAY | complete | ignore
    let cfg = ($env.PWD | path join $SRC "demo/relay/localhost.toml")
    print "==> starting relay container (moqdev/moq-relay)"
    ^docker run -d --name $RELAY -p 4443:4443/udp -p 4443:4443/tcp -v $"($cfg):/relay.toml:ro" moqdev/moq-relay /relay.toml | complete | ignore
  }

  # 2. Web deps. Vite runs UNDER bun, so no node is needed. The native
  #    webtransport polyfill's postinstall can fail — harmless, the browser app
  #    uses the platform WebTransport, never that Node shim.
  print "==> bun install (web deps; a native polyfill build may warn — ignored)"
  do { cd $SRC; ^bun install } | complete | ignore

  # 3. Web UI: Vite under bun, supervised by pitchfork so it outlives this command.
  ^pitchfork stop $WEB | complete | ignore
  let webdir = ($env.PWD | path join $SRC "demo/web")
  print $"==> starting web UI -> http://localhost:($PORT)"
  ^pitchfork run $WEB -f -- bash -c $"cd '($webdir)' && MOQ_NO_OPEN=1 VITE_RELAY_URL=($RELAY_URL) bun --bun vite --port ($PORT)" | complete | ignore

  print ""
  print $"  Publish: http://localhost:($PORT)/publish.html"
  print $"  Watch:   http://localhost:($PORT)/watch.html"
  print $"  Stats:   http://localhost:($PORT)/stats.html"
  print $"  Relay:   ($RELAY_URL)   container ($RELAY)"
  print "  Video:   mise run moq:demo -- pub    # Big Buck Bunny into /watch.html"
}

def "main down" [] {
  ^pitchfork stop $WEB | complete | ignore
  ^docker rm -f $RELAY | complete | ignore
  print "moq demo stopped: relay container + web daemon down."
}

def "main status" [] {
  print $"relay:  (if (relay-up) { 'running' } else { 'stopped' })"
  print "web (pitchfork):"
  for l in (^pitchfork list | complete | get stdout | lines | where {|l| $l | str contains $WEB }) { print $"  ($l)" }
}

# Publish a fragmented test video into the relay via the moq-cli CONTAINER. ffmpeg
# (host) remuxes to CMAF fMP4 and pipes to `moqdev/moq-cli publish`. Default Big
# Buck Bunny; pass `tos` for Tears of Steel.
def "main pub" [name: string = "bbb"] {
  ensure-src
  if (which ffmpeg | is-empty) {
    print -e "✗ ffmpeg not on PATH. Install it: brew install ffmpeg   (then re-run)."
    exit 1
  }
  let media = ($env.PWD | path join $SRC "demo/pub/media" $"($name).mp4")
  if not ($media | path exists) {
    mkdir ($media | path dirname)
    print $"==> downloading ($name).mp4 from vid.moq.dev"
    ^curl -fsSL $"https://vid.moq.dev/($name).mp4" -o $media
  }
  print $"==> publishing ($name).hang into ($RELAY_URL)   [Ctrl-C to stop]"
  ^bash -c $"ffmpeg -hide_banner -v error -stream_loop -1 -re -i '($media)' -c copy -f mp4 -movflags cmaf+separate_moof+delay_moov+skip_trailer+frag_every_frame - | docker run -i --network host moqdev/moq-cli publish --url ($RELAY_URL) --name ($name).hang fmp4"
}

def main [] {
  print "usage: mise run moq:demo -- <up|down|pub|status>"
  print "  up      relay (docker) + web UI -> http://localhost:5173/publish.html"
  print "  pub     publish Big Buck Bunny into the relay (needs ffmpeg)"
  print "  status  show relay + web state"
  print "  down    stop everything"
}
