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
  # connect/*.nu run top-level code (driven by `nu connect/<x>.nu`), so parse
  # them with nu-check rather than sourcing (which would execute them).
  for f in (glob connect/*.nu) {
    let r = (^nu -c $"nu-check ($f)" | complete)
    if (($r.stdout | str trim) != "true") { print $"   FAIL ($f):\n($r.stderr)"; $fails = ($fails | append $"parse ($f)") }
  }

  # Actually RUN each recipe prepare.nu (parse alone misses runtime errors like
  # literal parens in interpolated strings). Must exit 0 and print valid JSON.
  # VMU_SECRET_DRY keeps it from touching the keychain.
  print "==> recipe prepare.nu"
  for f in (glob recipes/*/prepare.nu) {
    let r = (with-env { DOMAIN: "ci.example.com", VMU_SECRET_DRY: "1" } { ^nu $f } | complete)
    let valid_json = (try { ($r.stdout | from json | describe) starts-with "record" } catch { false })
    if (($r.exit_code != 0) or (not $valid_json)) { print $"   FAIL ($f):\n($r.stderr | str trim)"; $fails = ($fails | append $"run ($f)") }
  }

  # Every recipe compose.yaml must be valid YAML.
  print "==> compose YAML"
  for f in ((glob recipes/*/compose.yaml) ++ ["compose.yaml" "caddy/compose.yaml"]) {
    let ok = (try { open $f | ignore; true } catch { false })
    if (not $ok) { print $"   FAIL ($f)"; $fails = ($fails | append $"yaml ($f)") }
  }

  print ""
  if ($fails | is-empty) {
    print "✓ CI passed"
  } else {
    print $"✗ CI failed: ($fails | str join ', ')"
    exit 1
  }
}
