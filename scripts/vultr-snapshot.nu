#!/usr/bin/env nu
# win-kvm state preservation: snapshot the Vultr BM's Windows disk via R2 transit
# (Vultr has no native hot-snapshot). Pipeline: ssh BM → gzip qcow2 → R2 →
# presign → `vultr-cli snapshot create-url` → poll → delete R2 transit object.
#
# ⚠️ UNVERIFIED PORT. Faithfully adapted from vm-servers/providers/vultr/
# snapshot-create.nu, but NOT run here (needs VULTR_API_KEY + R2 creds + a live
# BM). KEY DIFFERENCE vs vm-servers: the windows-kvm recipe stores the qcow2 in a
# named Docker volume, not /root/windows_storage — so we resolve the volume
# mountpoint with `docker volume inspect`. Verify on first real win-kvm run.
#
# Needs: R2_ENDPOINT, R2_BUCKET (mise.local.toml) + R2_ACCESS_KEY_ID,
# R2_SECRET_ACCESS_KEY (keychain) — set up via `mise run r2:bootstrap`.

def main [] {
  for v in ["R2_ENDPOINT" "R2_BUCKET"] {
    if (($env | get -o $v | default "") | is-empty) { print -e $"($v) not set — run `mise run r2:bootstrap`"; exit 1 }
  }
  let r2_id = (^fnox get R2_ACCESS_KEY_ID | complete)
  let r2_sec = (^fnox get R2_SECRET_ACCESS_KEY | complete)
  if $r2_id.exit_code != 0 or $r2_sec.exit_code != 0 { print -e "R2 creds missing in keychain — see r2:bootstrap"; exit 1 }

  let label = ($env.VULTR_LABEL? | default "win-kvm")
  let listing = (^fnox exec --if-missing ignore -- vultr-cli bare-metal list -o json | from json)
  let matches = ($listing.bare_metals? | default [] | where label == $label)
  if ($matches | is-empty) { print -e $"no Vultr BM labelled '($label)' — nothing to snapshot"; exit 1 }
  let ip = ($matches | first | get main_ip)
  let key = ($env.VULTR_SSH_KEY_FILE? | default "~/.ssh/id_ed25519" | path expand)

  let ts = (date now | format date "%Y%m%d-%H%M%S")
  let desc = $"win-kvm-($ts)"
  let s3_key = $"($desc).qcow2.gz"
  let access = ($r2_id.stdout | str trim)
  let secret = ($r2_sec.stdout | str trim)

  print $"snapshot: BM ($ip) → s3://($env.R2_BUCKET)/($s3_key) [expect 30-60 min]"

  # Resolve the qcow2 inside the named volume, clean-shut Windows, stream to R2.
  let tmpl = '
set -e
command -v aws >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq awscli; }
docker stop --timeout=120 windows 2>/dev/null || true
VOL=$(docker volume ls -q | grep -i windows_storage | head -1)
[ -z "$VOL" ] && { echo "no windows_storage volume found"; exit 1; }
DIR=$(docker volume inspect "$VOL" -f "{{.Mountpoint}}")
QCOW2=$(ls "$DIR"/*.qcow2 2>/dev/null | head -1)
[ -z "$QCOW2" ] && { echo "no qcow2 in $DIR"; exit 1; }
echo "  source: $QCOW2 ($(du -h "$QCOW2" | cut -f1))"
AWS_ACCESS_KEY_ID=__A__ AWS_SECRET_ACCESS_KEY=__S__ gzip -1 < "$QCOW2" | aws --endpoint-url __E__ s3 cp - s3://__B__/__K__ --no-progress
'
  let remote = ($tmpl
    | str replace --all "__A__" $access | str replace --all "__S__" $secret
    | str replace --all "__E__" $env.R2_ENDPOINT | str replace --all "__B__" $env.R2_BUCKET
    | str replace --all "__K__" $s3_key)

  print "→ streaming qcow2 to R2..."
  $remote | ^ssh -i $key -o StrictHostKeyChecking=accept-new $"root@($ip)" bash -s
  if ($env.LAST_EXIT_CODE? | default 0) != 0 { print -e "upload failed — R2 object may be partial"; exit 1 }

  print "→ presign + register with Vultr..."
  let url = (^fnox exec --if-missing ignore -- aws --endpoint-url $env.R2_ENDPOINT s3 presign $"s3://($env.R2_BUCKET)/($s3_key)" --expires-in 86400 | str trim)
  if ($url | is-empty) { print -e "presign empty"; exit 1 }
  let created = (^fnox exec --if-missing ignore -- vultr-cli snapshot create-url --url $url --description $desc -o json | from json)
  let snap_id = ($created.snapshot?.id? | default null)
  if $snap_id == null { print -e "no snapshot id from vultr-cli"; exit 1 }
  print $"  snapshot ($snap_id) registered — Vultr is fetching; check `vultr-cli snapshot list`."

  print "→ deleting R2 transit object once Vultr has copied it (do manually if Vultr is still fetching):"
  print $"  fnox exec -- aws --endpoint-url ($env.R2_ENDPOINT) s3 rm s3://($env.R2_BUCKET)/($s3_key)"
  do { nu state/log.nu deploy --cluster win-kvm --service $"snapshot:($desc)" } | ignore
}
