#!/usr/bin/env nu
# Hetzner ARM (cax) capacity tools. Run via mise (`arm:*`) which wraps these in
# `fnox exec` so HCLOUD_TOKEN is injected. ARM is frequently sold out in the EU
# locations, so check ALL datacenters (US + Singapore often have stock) and grab
# capacity the moment it appears.
#
#   mise run arm:check                 # availability matrix, all locations
#   mise run arm:grab -- <loc> [size]  # secure ONE box in a location (costs money)
#   mise run arm:secure -- [size]      # secure one box in EVERY available location
#   mise run arm:release -- <loc>      # delete a secured box
#   mise run arm:release-all           # delete all secured boxes

const SSH_KEY = "gedw99_hetzner"   # matches tofu var ssh_key_name

# Which cax sizes are available where (by location).
def cax-availability [] {
  let cax = (^hcloud server-type list -o json | from json | where name =~ '^cax' | select id name)
  ^hcloud datacenter list -o json | from json | each {|dc|
    let avail = $dc.server_types.available
    {
      location: $dc.location.name
      city: $dc.location.city
      cax: ($cax | where {|t| $t.id in $avail } | get name | sort)
    }
  } | sort-by location
}

# main check — availability matrix.
def "main check" [] {
  print "Hetzner ARM (cax) availability:"
  for r in (cax-availability) {
    let mark = (if ($r.cax | is-empty) { "✗ none" } else { $"✓ ($r.cax | str join ', ')" })
    print $"  ($r.location | fill -a left -w 8) ($r.city | fill -a left -w 16) ($mark)"
  }
}

# create + keep a cax box in a location (→ billing until released).
def grab-one [location: string, size: string] {
  let name = $"arm-reserve-($location)"
  print $"==> securing ($size) in ($location) as ($name) ..."
  ^hcloud server create --name $name --type $size --image ubuntu-24.04 --location $location --ssh-key $SSH_KEY
  print $"✓ ($name) secured. Stop billing: mise run arm:release -- ($location)"
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

# main watch — poll until cax appears in a location, then grab it (and keep
# grabbing new locations as they free up). This is "secure them for me": leave it
# running and it snaps up ARM the moment Hetzner has stock. COSTS MONEY per grab.
def "main watch" [size: string = "cax11", --interval: int = 60] {
  print $"==> watching for ($size); grabbing in any location with stock every ($interval)s. Ctrl-C to stop."
  loop {
    let here = (cax-availability | where {|r| $size in $r.cax } | get location)
    let have = (^hcloud server list -o json | from json | where name =~ '^arm-reserve-' | get name)
    for loc in $here {
      if not ($"arm-reserve-($loc)" in $have) {
        print $"  [(date now | format date '%H:%M:%S')] ($size) appeared in ($loc) — grabbing!"
        grab-one $loc $size
      }
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

def main [] { main check }
