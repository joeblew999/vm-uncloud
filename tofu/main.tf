terraform {
  required_version = ">= 1.6"
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

# Tokens are read from the environment (HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN),
# injected by `fnox exec` from the keychain. No token args here on purpose —
# keeps secrets out of state/vars and matches the cross-repo fnox contract.
provider "hcloud" {}

provider "cloudflare" {}

# Reference an SSH key already uploaded to your Hetzner project.
# Create one in the console (Security -> SSH Keys) and put its name in var.ssh_key_name.
data "hcloud_ssh_key" "this" {
  name = var.ssh_key_name
}

# Firewall: SSH in, HTTP/HTTPS for Caddy ingress, UDP/443 for HTTP/3,
# and the WireGuard port for the inter-machine mesh.
resource "hcloud_firewall" "uncloud" {
  name = "${var.cluster_name}-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = var.ssh_allowed_ips
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # WireGuard mesh between Uncloud machines.
  rule {
    direction  = "in"
    protocol   = "udp"
    port       = tostring(var.wireguard_port)
    source_ips = ["0.0.0.0/0", "::/0"]
  }
  # RDP for Windows desktop nodes only — restricted to the SSH allowlist (set
  # ssh_allowed_ips to your IP). dockur exposes RDP on 3389 tcp+udp.
  dynamic "rule" {
    for_each = var.windows ? ["tcp", "udp"] : []
    content {
      direction  = "in"
      protocol   = rule.value
      port       = "3389"
      source_ips = var.ssh_allowed_ips
    }
  }
}

resource "hcloud_server" "node" {
  count        = var.node_count
  name         = "${var.cluster_name}-${count.index + 1}"
  server_type  = var.server_type
  image        = var.image
  location     = var.location
  ssh_keys     = [data.hcloud_ssh_key.this.id]
  firewall_ids = [hcloud_firewall.uncloud.id]

  # cloud-init bootstrap: installs the Uncloud machine daemon (Docker + uncloudd)
  # on first boot, so the box is a ready Uncloud machine. `uc machine init` then
  # connects over SSH to bootstrap the cluster (the install step is idempotent).
  user_data = file("${path.module}/../cloud-init/uncloud.yaml")

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }

  labels = {
    managed_by = "vm-uncloud"
    cluster    = var.cluster_name
  }

  # Readiness wait lives HERE, in tofu — not in a shell poll loop. Terraform's
  # connection block retries SSH natively until the box is reachable, then
  # `cloud-init status --wait` BLOCKS server-side until cloud-init finishes.
  # So `tofu apply` returns only when the machine is actually ready for
  # `uc machine init`. (`|| true`: wait regardless of cloud-init's exit status —
  # the real install is done by uc; we only need to know it's finished.)
  connection {
    type        = "ssh"
    host        = self.ipv4_address
    user        = "root"
    private_key = file(pathexpand(var.ssh_private_key_file))
    timeout     = "5m"
  }
  provisioner "remote-exec" {
    inline = ["cloud-init status --wait || true"]
  }
}

# One wildcard A record: *.<domain> -> the ingress node. Every subdomain
# (app, api, wordpress, anything) resolves to the box with zero per-host setup.
# Caddy obtains a single *.<domain> wildcard cert via the Cloudflare DNS-01
# challenge (no HTTP-01, no port-80/propagation timing, no per-host rate limits).
# proxied = false so Caddy terminates TLS directly (DNS-only / grey cloud).
resource "cloudflare_dns_record" "wildcard" {
  count = (var.domain == "" || var.windows) ? 0 : 1

  zone_id = var.cloudflare_zone_id
  name    = "*.${var.domain}"
  type    = "A"
  content = hcloud_server.node[0].ipv4_address
  ttl     = 60
  proxied = false
}

# Windows desktop nodes get a single windows.<domain> A record instead of the
# wildcard (which belongs to the cluster). RDP/viewer/GUI resolve the node here.
resource "cloudflare_dns_record" "windows" {
  count = (var.domain != "" && var.windows) ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = "windows.${var.domain}"
  type    = "A"
  content = hcloud_server.node[0].ipv4_address
  ttl     = 60
  proxied = false
}

# Optional apex record (example.com itself), off by default.
resource "cloudflare_dns_record" "apex" {
  count = (var.domain != "" && var.dns_apex) ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = var.domain
  type    = "A"
  content = hcloud_server.node[0].ipv4_address
  ttl     = 60
  proxied = false
}
