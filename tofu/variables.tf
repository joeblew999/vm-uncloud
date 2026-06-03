# Secrets (HCLOUD_TOKEN, CLOUDFLARE_API_TOKEN) are NOT tofu variables — the
# providers read them straight from the environment, injected by `fnox exec`.

# Cloudflare zone the records live in. Leave empty to skip DNS entirely
# (set app_hostnames = [] too) — useful for infra-only / smoke runs.
variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for your domain (empty = no DNS)"
  type        = string
  default     = ""
}

variable "domain" {
  description = "Apex domain managed in the above zone, e.g. example.com (empty = no DNS)"
  type        = string
  default     = ""
}

variable "app_hostnames" {
  description = <<-EOT
    Subdomain labels to create A records for, each pointing at the ingress node.
    Use "@" for the apex domain itself. Example: ["app", "api", "www"].
    These are the hostnames you then publish services on, e.g.
      uc run -p app.example.com:8000/https <image>
  EOT
  type        = list(string)
  default     = ["app"]
}

# Hetzner machine shape.
variable "cluster_name" {
  description = "Name prefix for servers, firewall, and the uncloud context"
  type        = string
  default     = "uncloud"
}

variable "node_count" {
  description = "Number of Hetzner servers (1 = single node; >1 = WireGuard mesh)"
  type        = number
  default     = 1
}

variable "server_type" {
  description = "Hetzner server type. cpx22 = 2 vCPU / 4GB x86; ARM alt: cax11. Verified available on this account; run `hcloud server-type list` if unsure."
  type        = string
  default     = "cpx22"
}

variable "image" {
  description = "Base OS image (Ubuntu/Debian only, per Uncloud requirements)"
  type        = string
  default     = "ubuntu-24.04"
}

variable "location" {
  description = "Hetzner location (fsn1, nbg1, hel1, ash, hil, sin)"
  type        = string
  default     = "fsn1"
}

variable "ssh_key_name" {
  description = "Name of an existing SSH key in your Hetzner project"
  type        = string
}

variable "ssh_allowed_ips" {
  description = "CIDRs allowed to SSH in (default: anywhere — tighten to your IP)"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "wireguard_port" {
  description = "UDP port for the Uncloud WireGuard mesh"
  type        = number
  default     = 51820
}
