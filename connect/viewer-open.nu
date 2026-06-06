# Open dockur's noVNC web viewer (port 8006) — Windows install progress, then
# the desktop. 8006 has NO auth and is NOT exposed on the firewall, so we reach
# it over an SSH tunnel (localhost:8006 → node:8006), then open the browser.

def os-open [url: string] {
    match $nu.os-info.name {
        "macos"   => { ^open $url }
        "linux"   => { ^xdg-open $url }
        "windows" => { ^cmd /c start "" $url }
        _ => { print $"open ($url) in your browser" }
    }
}

let ip = (nu connect/ip.nu | str trim)
if ($ip | is-empty) { print -e "could not resolve the Windows node IP (is it up? set WIN_NODE)"; exit 1 }

let key = ($env.WIN_SSH_KEY? | default "~/.ssh/gedw99_hetzner" | path expand)
let key_flag = (if ($key | path exists) { [-i $key] } else { [] })

print $"opening SSH tunnel localhost:8006 → ($ip):8006 ..."
# -f: background after auth, -N: no remote command, -L: local forward.
let r = (^ssh -f -N -o StrictHostKeyChecking=accept-new -L 8006:localhost:8006 ...$key_flag $"root@($ip)" | complete)
if $r.exit_code != 0 {
    print -e $"tunnel failed. Open it manually:\n  ssh -N -L 8006:localhost:8006 root@($ip)\nthen browse http://localhost:8006/"
    exit 1
}
print "tunnel up (backgrounded). Opening http://localhost:8006/"
print "  close it later with:  pkill -f '8006:localhost:8006'"
os-open "http://localhost:8006/"
