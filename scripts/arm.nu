#!/usr/bin/env nu
# Hetzner ARM (cax) capacity tools. Run via mise (`arm:*`) which wraps these in
# `fnox exec` so HCLOUD_TOKEN is injected.
#
# cax (ARM) is offered ONLY in the 3 EU locations — nbg1 / hel1 / fsn1. The US
# (ash, hil) and Singapore (sin) datacenters do NOT offer ARM at all (cax isn't
# even in their `supported` set), so don't expect stock there. ARM is frequently
# 100% sold out across all 3 EU sites for long stretches — a `check` showing
# "sold out" everywhere is the normal, correct state, not a bug. The watch polls
# every datacenter and grabs the instant any EU site restocks.
#
# Lifecycle of a scarce box: grab → adopt ⇄ evict (keep the box) → release.
# Hetzner is the SSOT for what we hold (`arm:list`); no local record is kept.
#
#   mise run arm:check                 # availability matrix, all locations
#   mise run arm:list                  # the cax boxes we hold right now (from Hetzner)
#   mise run arm:grab -- <loc> [size]  # secure ONE box in a location (costs money)
#   mise run arm:secure -- [size]      # secure one box in EVERY available location
#   mise run arm:adopt -- <loc>        # join a held box INTO the uncloud cluster
#   mise run arm:evict -- <loc>        # remove from cluster but KEEP the box (re-adoptable)
#   mise run arm:release -- <loc>      # DELETE a secured box (stops billing)
#   mise run arm:release-all           # delete all secured boxes

const SSH_KEY = "gedw99_hetzner"   # matches tofu var ssh_key_name

# Which cax sizes are available where (by location). `cax` = orderable right now;
# `supported` = offered at that site at all (empty ⇒ no ARM there, e.g. US/SIN).
def cax-availability [] {
  let cax = (^hcloud server-type list -o json | from json | where name =~ '^cax' | select id name)
  ^hcloud datacenter list -o json | from json | each {|dc|
    {
      location: $dc.location.name
      city: $dc.location.city
      cax: ($cax | where {|t| $t.id in $dc.server_types.available } | get name | sort)
      supported: ($cax | where {|t| $t.id in $dc.server_types.supported } | get name | sort)
    }
  } | sort-by location
}

# main check — availability matrix. Distinguishes "sold out" (offered here but no
# stock) from "no ARM" (cax not offered at this site at all).
def "main check" [] {
  print "Hetzner ARM (cax) availability:"
  for r in (cax-availability) {
    let mark = (if ($r.supported | is-empty) {
      "— no ARM at this site"
    } else if ($r.cax | is-empty) {
      "✗ sold out"
    } else {
      $"✓ ($r.cax | str join ', ')"
    })
    print $"  ($r.location | fill -a left -w 8) ($r.city | fill -a left -w 16) ($mark)"
  }
}

# create + keep a cax box in a location (→ billing until released).
def grab-one [location: string, size: string] {
  let name = $"arm-reserve-($location)"
  print $"==> securing ($size) in ($location) as ($name) ..."
  ^hcloud server create --name $name --type $size --image ubuntu-24.04 --location $location --ssh-key $SSH_KEY
  # No local record kept — Hetzner is the single source of truth. The box itself
  # (name, type, DC, IP, status, created-at) IS the record; see `mise run arm:list`.
  print $"✓ ($name) secured. See it: mise run arm:list. Stop billing: mise run arm:release -- ($location)"
}

# main list — the cax boxes we hold, straight from Hetzner (the SSOT). No local
# state: `created` is when it was grabbed; everything here is live.
def "main list" [] {
  let boxes = (^hcloud server list -o json | from json | where name =~ '^arm-reserve-')
  if ($boxes | is-empty) { print "No ARM boxes held (arm-reserve-*). The watcher grabs one per EU site when stock appears."; return }
  $boxes | each {|s|
    { name: $s.name, type: $s.server_type.name, dc: $s.datacenter.name, ip: $s.public_net.ipv4.ip, status: $s.status, created: $s.created }
  } | sort-by dc | table
}

# main grab — secure ONE cax box in a location.
def "main grab" [location: string, size: string = "cax11"] { grab-one $location $size }

# main secure — grab one box in EVERY location that currently has cax. COSTS MONEY.
def "main secure" [size: string = "cax11"] {
  let here = (cax-availability | where {|r| $size in $r.cax })
  if ($here | is-empty) { print $"✗ ($size) not available in any location right now."; return }
  print $"==> securing ($size) in: ($here | get location | str join ', ')"
  for r in $here { grab-one $r.location $size }
}

# main watch — poll until cax appears, then auto-grab UP TO `--max` boxes TOTAL
# (default 1), at most one per location, then idle. This is the hard cap that
# stops it ever grabbing "more and more": once it holds --max arm-reserve-* boxes
# it grabs nothing more. Self-heals — if you release one, it re-grabs to keep
# --max. COSTS MONEY per grab. Leave running; Ctrl-C (or `arm:watch:down`) to stop.
def "main watch" [size: string = "cax11", --interval: int = 5, --max: int = 1] {
  print $"==> watching for ($size); auto-grabbing up to ($max) total \(≤1 per location\) every ($interval)s. Ctrl-C to stop."
  loop {
    # A single transient API/DNS hiccup must NOT kill a long-running watch — log
    # it and retry on the next tick.
    try {
      let have = (^hcloud server list -o json | from json | where name =~ '^arm-reserve-' | get name)
      # Only look for stock while UNDER the cap — this is what bounds total grabs.
      if ($have | length) < $max {
        let here = (cax-availability | where {|r| $size in $r.cax } | get location)
        mut held = $have
        for loc in $here {
          if ($held | length) >= $max { break }
          if not ($"arm-reserve-($loc)" in $held) {
            let n = (($held | length) + 1)
            print $"  [(date now | format date '%H:%M:%S')] ($size) appeared in ($loc) — grabbing ($n)/($max)!"
            grab-one $loc $size
            $held = ($held | append $"arm-reserve-($loc)")
          }
        }
      }
    } catch {|e|
      print $"  [(date now | format date '%H:%M:%S')] transient error — retrying in ($interval)s: ($e.msg)"
    }
    sleep ($interval * 1sec)
  }
}

# main release — delete a secured box.
def "main release" [location: string] {
  ^hcloud server delete $"arm-reserve-($location)"
  print $"✓ released arm-reserve-($location)"
}

# main release-all — delete every secured box.
def "main release-all" [] {
  let boxes = (^hcloud server list -o json | from json | where name =~ '^arm-reserve-' | get name)
  if ($boxes | is-empty) { print "no secured arm boxes."; return }
  for b in $boxes { ^hcloud server delete $b; print $"✓ released ($b)" }
}

# main adopt — join a held cax box INTO the uncloud cluster (uncloud machine add):
# SSH in as root, install the daemon, join the WireGuard mesh. The box stays a
# Hetzner server we own; this only makes it a cluster member. Requires an existing
# cluster (run `cluster:up` first) whose context is configured locally.
# ⚠ UNVERIFIED end-to-end — wired from the documented `machine add` flags but not
# yet run against a live cluster + held box (ARM has been sold out).
def "main adopt" [location: string, --context: string = "", --ssh-key: string = ""] {
  let server = $"arm-reserve-($location)"
  let ip = (try { ^hcloud server ip $server | str trim } catch { "" })
  if ($ip | is-empty) { print -e $"✗ no held box ($server) — grab one first \(see arm:list\)."; exit 1 }
  mut flags = []
  if ($context | is-not-empty) { $flags = ($flags | append [-c $context]) }
  if ($ssh_key | is-not-empty) { $flags = ($flags | append [-i $ssh_key]) }
  print $"==> adopting ($server) at ($ip) into the cluster as machine ($server) ..."
  ^uc machine add $"root@($ip)" -n $server ...$flags -y
  print $"✓ ($server) joined the cluster. Evict but keep the box: mise run arm:evict -- ($location)"
}

# main evict — remove a cax box from the cluster but KEEP the Hetzner server, so
# you keep the scarce ARM capacity. `uncloud machine rm` resets the box (re-adopt
# any time). To actually delete the server and stop billing, use `arm:release`.
# ⚠ UNVERIFIED end-to-end (see adopt).
def "main evict" [location: string, --context: string = ""] {
  let server = $"arm-reserve-($location)"
  mut flags = []
  if ($context | is-not-empty) { $flags = ($flags | append [-c $context]) }
  print $"==> evicting ($server) from the cluster — the Hetzner server stays \(still billing\) ..."
  ^uc machine rm $server ...$flags -y
  print $"✓ ($server) left the cluster; box retained. Re-adopt: mise run arm:adopt -- ($location). Delete: mise run arm:release -- ($location)"
}

def main [] { main check }
