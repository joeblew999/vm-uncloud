#!/usr/bin/env nu
# Deploy services defined in compose.yaml to the cluster.

def main [] {
  if not ("compose.yaml" | path exists) {
    print "ERROR: compose.yaml not found in the repo root."
    exit 1
  }
  print "==> uc deploy -f compose.yaml"
  ^uc deploy -f compose.yaml
  print ""
  print "Deployed. Check status with: mise run status"
}
