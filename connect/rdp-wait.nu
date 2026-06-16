# Block until the Windows node accepts TCP on 3389 — the signal Windows
# finished OOBE and RDP is up. Polls every 30s, 90 min max. OS-native desktop
# notification on success/timeout. Target IP from connect/ip.nu.

def notify [title: string, body: string, success: bool] {
    match $nu.os-info.name {
        "macos" => {
            let sound = (if $success { "Glass" } else { "Basso" })
            ^osascript -e $"display notification \"($body)\" with title \"($title)\" sound name \"($sound)\"" out+err> /dev/null
        }
        "linux" => {
            if (which notify-send | length) > 0 {
                ^notify-send $title $body out+err> /dev/null
            }
        }
        "windows" => {
            let ps = $"[reflection.assembly]::loadwithpartialname\('System.Windows.Forms'\) | out-null; $n = new-object system.windows.forms.notifyicon; $n.icon = [system.drawing.systemicons]::information; $n.visible = $true; $n.showballoontip\(5000, '($title)', '($body)', 'Info'\)"
            ^powershell -NoProfile -Command $ps out+err> /dev/null
        }
        _ => { }
    }
}

def port-open [host: string, port: int] {
    if $nu.os-info.name == "windows" {
        let r = (^powershell -NoProfile -Command $"\(Test-NetConnection -ComputerName ($host) -Port ($port) -WarningAction SilentlyContinue\).TcpTestSucceeded" | complete)
        ($r.stdout | str trim | str downcase) == "true"
    } else {
        let r = (^nc -z -w 3 $host ($port | into string) | complete)
        $r.exit_code == 0
    }
}

let ip = (nu connect/ip.nu | str trim)
if ($ip | is-empty) { print -e "could not resolve the Windows node IP (is it up? set WIN_NODE)"; exit 1 }

print $"polling ($ip):3389 \(every 30s, max 90 min\)..."

job spawn {
    mut elapsed = 0
    let max = 90 * 60
    loop {
        if (port-open $ip 3389) {
            {status: "ready", elapsed: $elapsed} | job send 0
            return
        }
        if $elapsed >= $max {
            {status: "timeout", elapsed: $elapsed} | job send 0
            return
        }
        sleep 30sec
        $elapsed = $elapsed + 30
        print -n $"[t+($elapsed)s] not yet\r"
    }
}

let result = (job recv --timeout 91min)
if $result.status == "ready" {
    print $"\n[t+($result.elapsed)s] 3389 accepting — Windows is RDP-ready"
    notify "vm-uncloud" "Windows is RDP-ready — run mise run win:rdp" true
} else {
    print $"\n[t+($result.elapsed)s] timed out — investigate via mise run win:viewer"
    notify "vm-uncloud" "RDP wait timed out after 90 min" false
    exit 1
}
