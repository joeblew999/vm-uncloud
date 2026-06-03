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

  print ""
  if ($fails | is-empty) {
    print "✓ CI passed"
  } else {
    print $"✗ CI failed: ($fails | str join ', ')"
    exit 1
  }
}
