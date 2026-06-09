# Block until the dev container accepts SSH on its published port — the signal
# the dev-linux recipe is up and reachable for Remote-SSH / rsync. Polls every
# 10s, 10 min max. Resolves the node IP from its name (DEV_NODE, default dev-1).

def port-open [host: string, port: int] {
    if $nu.os-info.name == "windows" {
        let r = (^powershell -NoProfile -Command $"\(Test-NetConnection -ComputerName ($host) -Port ($port) -WarningAction SilentlyContinue\).TcpTestSucceeded" | complete)
        ($r.stdout | str trim | str downcase) == "true"
    } else {
        let r = (^nc -z -w 3 $host ($port | into string) | complete)
        $r.exit_code == 0
    }
}

let node = ($env.DEV_NODE? | default "dev-1")
let port = ($env.DEV_PORT? | default "2222" | into int)
let ip = (^fnox exec --if-missing ignore -- hcloud server ip $node | str trim)
if ($ip | is-empty) { print -e $"could not resolve ($node) IP (is the dev node up? mise run dev:up)"; exit 1 }

print $"polling ($ip):($port) \(every 10s, max 10 min\)..."
mut elapsed = 0
let max = 10 * 60
loop {
    if (port-open $ip $port) {
        print $"\n[t+($elapsed)s] ($port) accepting — dev container is SSH-ready"
        print "next: mise run dev:code   (VS Code Remote-SSH)   or   mise run dev:ssh"
        exit 0
    }
    if $elapsed >= $max { print -e $"\n[t+($elapsed)s] timed out — check: mise run dev:status"; exit 1 }
    sleep 10sec
    $elapsed = $elapsed + 10
    print -n $"[t+($elapsed)s] not yet\r"
}
