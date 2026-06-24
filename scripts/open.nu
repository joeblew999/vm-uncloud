#!/usr/bin/env nu
# Open a URL (or file) in the host OS's default app — OS-neutral, no hardcoded
# paths (matches connect/viewer-open.nu's pattern). Used by dashboard deep-link
# tasks so `mise run <thing>:dashboard` drops you on the exact page.
#
#   nu scripts/open.nu https://my.vultr.com/settings/#settingsapi

def main [url: string] {
  match $nu.os-info.name {
    "macos"   => { ^open $url }
    "linux"   => { ^xdg-open $url }
    "windows" => { ^cmd /c start "" $url }
    _ => { print $"open this in your browser: ($url)" }
  }
  print -e $"→ opened ($url)"
}
