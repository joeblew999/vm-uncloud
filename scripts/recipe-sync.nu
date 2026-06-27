#!/usr/bin/env nu
# Shallow-clone (or update) every recipe source listed in recipes.toml into
# .src/<name>. We reference upstream repos rather than forking them — same
# overlay pattern as our other repos. .src/ is gitignored.

export def sources [] {
  if not ("recipes.toml" | path exists) { return [] }
  (open recipes.toml | get sources? | default [])
}

def main [] {
  let srcs = (sources)
  if ($srcs | is-empty) {
    print "No sources in recipes.toml."
    return
  }
  for s in $srcs {
    let dir = $".src/($s.name)"
    if ($dir | path exists) {
      print $"==> Updating ($dir)"
      ^git -C $dir pull --ff-only
    } else {
      print $"==> Cloning ($s.url) -> ($dir)"
      mkdir .src
      ^git clone --depth 1 $s.url $dir
    }
  }
}
