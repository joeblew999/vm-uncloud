#!/usr/bin/env nu
# Shallow-clone (or update) psviderski/uncloud-recipes into .src/uncloud-recipes.
# We reference upstream rather than forking it — same overlay pattern as our
# other repos. .src/ is gitignored.

const REPO = "https://github.com/psviderski/uncloud-recipes"

def main [] {
  let dir = ".src/uncloud-recipes"
  if ($dir | path exists) {
    print $"==> Updating ($dir)"
    ^git -C $dir pull --ff-only
  } else {
    print $"==> Cloning ($REPO) -> ($dir)"
    mkdir .src
    ^git clone --depth 1 $REPO $dir
  }
}
