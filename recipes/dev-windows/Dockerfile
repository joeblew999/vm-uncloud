# dev-windows image = dockur/windows + baked first-boot provisioning.
#
# dockur runs C:\OEM\install.bat once after Windows setup. We must SHIP that file
# as an image layer, not a bind mount: recipes deploy to a REMOTE node, where a
# local `./oem` path does not exist (a `- ./oem:/oem` volume would resolve on the
# node's filesystem and be empty). `uc deploy` builds this and pushes only the
# small added layer.
FROM dockurr/windows:5.15

COPY oem/ /oem/
