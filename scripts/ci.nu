#!/usr/bin/env nu
# Repo checks — the SAME thing runs locally (`mise run ci`) and in CI
# (.github/workflows/check.yml is a thin wrapper around this). No cloud
# credentials needed: tofu fmt + validate, and a parse check of every script.

def main [] {
  mut fails = []

  print "==> tofu fmt -check"
  let fmt = (^tofu -chdir=tofu fmt -check -recursive | complete)
  if $fmt.exit_code != 0 {
    print $"   unformatted:\n($fmt.stdout)"
    $fails = ($fails | append "tofu fmt")
  }

  print "==> tofu validate"
  ^tofu -chdir=tofu init -backend=false -input=false out+err> /dev/null
  let val = (^tofu -chdir=tofu validate | complete)
  print $"   ($val.stdout | str trim)"
  if $val.exit_code != 0 { print $val.stderr; $fails = ($fails | append "tofu validate") }
  rm -rf tofu/.terraform tofu/.terraform.lock.hcl

  print "==> nushell parse"
  for f in ((ls scripts/*.nu | get name) ++ ["state/log.nu"]) {
    let r = (^nu -c $"source ($f)" | complete)
    if $r.exit_code != 0 { print $"   FAIL ($f):\n($r.stderr)"; $fails = ($fails | append $"parse ($f)") }
  }

  # Actually RUN each recipe prepare.nu (parse alone misses runtime errors like
  # literal parens in interpolated strings). Must exit 0 and print valid JSON.
  print "==> recipe prepare.nu"
  for f in (glob examples/*/prepare.nu) {
    let r = (with-env { DOMAIN: "ci.example.com" } { ^nu $f } | complete)
    let ok = ($r.exit_code == 0) and ((do { $r.stdout | from json } | describe) starts-with "record")
    if not $ok { print $"   FAIL ($f):\n($r.stderr | str trim)"; $fails = ($fails | append $"run ($f)") }
  }

  print ""
  if ($fails | is-empty) {
    print "✓ CI passed"
  } else {
    print $"✗ CI failed: ($fails | str join ', ')"
    exit 1
  }
}
