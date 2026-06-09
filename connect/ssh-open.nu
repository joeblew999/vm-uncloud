# Open an interactive SSH session into the dev container (terminal entry point —
# the VS Code-free path). Resolves the node IP from DEV_NODE (default dev-1) and
# connects as DEV_USER on DEV_PORT, landing in /workspace.

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
let ip = (^fnox exec --if-missing ignore -- hcloud server ip $node | str trim)
if ($ip | is-empty) { print -e $"could not resolve ($node) IP (is the dev node up? mise run dev:up)"; exit 1 }

let key = (dev-key)
let key_flag = (if ($key | is-empty) { [] } else { [-i $key] })
print $"ssh -p ($port) ($user)@($ip)  -> /workspace"
^ssh -p $port -o StrictHostKeyChecking=accept-new ...$key_flag $"($user)@($ip)"
