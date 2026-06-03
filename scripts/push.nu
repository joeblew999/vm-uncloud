#!/usr/bin/env nu
# Ship local Docker images to the cluster using uncloud's BUILT-IN registry
# (unregistry) — no external registry, only missing layers transfer.
#
#   mise run push                 # uc build --push  (build Compose services locally + push to machines)
#   mise run push myapp:1.2.3     # uc image push <image>  (push an image you already built)
#
# OrbStack / Docker Desktop is just the local Docker daemon `uc build` uses.

def main [image?: string] {
  if ($image | is-empty) {
    print "==> uc build --push   (building Compose services locally + pushing to the cluster)"
    ^uc build --push
  } else {
    print $"==> uc image push ($image)"
    ^uc image push $image
  }
  print ""
  print "Pushed. Reference the image in compose.yaml and: mise run deploy"
}
