#!/usr/bin/env nu
# Make the booted Vultr BM an uncloud machine in the win-kvm context. Run after
# win-kvm:up once win-kvm:ip shows an address. RDP-only node → --no-caddy --no-dns.

def main [] {
  let ip = (with-env { WIN_PROVIDER: "vultr" } { ^nu connect/ip.nu } | str trim)
  if ($ip | is-empty) { print -e "no IP yet — the BM is still booting (try win-kvm:ip again)"; exit 1 }
  let key = ($env.VULTR_SSH_KEY_FILE? | default "~/.ssh/id_ed25519" | path expand)
  ^ssh-keygen -R $ip out+err> /dev/null
  print $"==> uc machine init root@($ip) --context win-kvm --no-dns --no-caddy"
  # PTY-wrap so the readiness spinner survives a non-TTY shell (uncloud#386).
  let cmd = ["uc" "machine" "init" $"root@($ip)" "--context" "win-kvm" "--name" "win-kvm-1" "--no-dns" "--no-caddy" "-i" $key "-y"]
  if $nu.os-info.name == "macos" { ^script -q /dev/null ...$cmd } else { ^script -qec ($cmd | str join " ") /dev/null }
  print "win-kvm node joined. Next: mise run win-kvm:deploy"
}
