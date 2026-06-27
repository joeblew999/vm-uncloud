#!/usr/bin/env nu
# Ship local Docker images to the cluster using uncloud's BUILT-IN registry
# (unregistry) — no external registry, only missing layers transfer.
#
#   mise run cluster:push                 # uncloud build --push  (build Compose services locally + push to machines)
#   mise run cluster:push myapp:1.2.3     # uncloud image push <image>  (push an image you already built)
#
# OrbStack / Docker Desktop is just the local Docker daemon `uncloud build` uses.

def main [image?: string] {
  if ($image | is-empty) {
    print "==> uncloud build --push   (building Compose services locally + pushing to the cluster)"
    ^uncloud build --push
  } else {
    print $"==> uncloud image push ($image)"
    ^uncloud image push $image
  }
  print ""
  print "Pushed. Reference the image in compose.yaml and: mise run cluster:deploy"
}
