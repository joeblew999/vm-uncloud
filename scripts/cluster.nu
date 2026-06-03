# Single source of truth for the cluster domain: it's set ONCE in
# tofu/terraform.tfvars and read back from tofu state here. Compose files use
# ${DOMAIN}; the deploy/recipe scripts inject it — no hostname is hardcoded.
# Returns "" if there's no domain / no state. Callers should load-env (r2-creds)
# first so `tofu output` can read remote state.

export def cluster-domain [] {
  let r = (^tofu -chdir=tofu output -raw domain | complete)
  if ($r.exit_code == 0) { ($r.stdout | str trim) } else { "" }
}
