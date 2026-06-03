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
}

# Cloudflare A records. Each hostname in var.app_hostnames points at the first
# node's public IPv4 — that's the machine running Caddy (ingress). For a real
# multi-node HA ingress you'd front these with a load balancer; for a single
# ingress node this is exactly right.
resource "cloudflare_dns_record" "app" {
  for_each = toset(var.app_hostnames)

  zone_id = var.cloudflare_zone_id
  name    = each.value == "@" ? var.domain : "${each.value}.${var.domain}"
  type    = "A"
  content = hcloud_server.node[0].ipv4_address
  ttl     = 60
  proxied = false # Caddy terminates TLS via Let's Encrypt; keep DNS-only (grey cloud).
}
