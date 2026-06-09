# Open VS Code Remote-SSH into the dev container at /workspace. Writes a managed
# Host alias into ~/.ssh/config (so the custom port + key + user are picked up
# without flags), then launches `code --remote ssh-remote+<alias> <folder>`.

def dev-key [] {
    let explicit = ($env.DEV_SSH_KEY? | default "")
    if ($explicit | is-not-empty) { return ($explicit | path expand) }
    let cands = (["~/.ssh/id_ed25519" "~/.ssh/gedw99_hetzner" "~/.ssh/id_rsa"]
        | each {|p| $p | path expand } | where {|p| $p | path exists })
    if ($cands | is-empty) { "" } else { $cands | first }
}

let node = ($env.DEV_NODE? | default "dev-1")
let port = ($env.DEV_PORT? | default "2222")
let user = ($env.DEV_USER? | default "vscode")
let alias = ($env.DEV_SSH_ALIAS? | default "vmu-dev")
let folder = ($env.DEV_REMOTE_DIR? | default "/workspace")
let ip = (^fnox exec --if-missing ignore -- hcloud server ip $node | str trim)
if ($ip | is-empty) { print -e $"could not resolve ($node) IP (is the dev node up? mise run dev:up)"; exit 1 }

let key = (dev-key)

# Upsert a managed Host block in ~/.ssh/config (markers include the alias so
# several dev nodes can coexist). Rewritten on every run so the IP stays current.
let begin = $"# >>> vm-uncloud dev ($alias) >>>"
let end = $"# <<< vm-uncloud dev ($alias) <<<"
let block = ([
    $begin
    $"Host ($alias)"
    $"    HostName ($ip)"
    $"    User ($user)"
    $"    Port ($port)"
    (if ($key | is-empty) { "" } else { $"    IdentityFile ($key)" })
    "    StrictHostKeyChecking accept-new"
    $end
] | where {|l| $l != "" } | str join "\n")

let cfg = ("~/.ssh/config" | path expand)
mkdir ("~/.ssh" | path expand)
let existing = (if ($cfg | path exists) { open --raw $cfg } else { "" })

# Drop any prior managed block for this alias, line by line (avoids regex-escaping
# the marker parens), then append the fresh one.
mut out = []
mut skip = false
for l in ($existing | lines) {
    if $l == $begin { $skip = true; continue }
    if $l == $end { $skip = false; continue }
    if not $skip { $out = ($out | append $l) }
}
let cleaned = ($out | str join "\n" | str trim)
let final = (([$cleaned $block] | where {|s| ($s | str trim) != "" } | str join "\n\n") + "\n")
$final | save -f $cfg
print $"~/.ssh/config: Host '($alias)' -> ($user)@($ip):($port)"

if (which code | length) > 0 {
    print $"opening VS Code: code --remote ssh-remote+($alias) ($folder)"
    ^code --new-window --remote $"ssh-remote+($alias)" $folder
} else {
    print "VS Code 'code' CLI not found. Connect manually:"
    print $"  code --remote ssh-remote+($alias) ($folder)"
    print $"  or plain terminal:  ssh ($alias)"
}
