output "node_ipv4" {
  description = "Public IPv4 of every node, in order"
  value       = hcloud_server.node[*].ipv4_address
}

output "node_ipv6" {
  description = "Public IPv6 of every node, in order"
  value       = hcloud_server.node[*].ipv6_address
}

output "ingress_ipv4" {
  description = "IPv4 of the first node (runs Caddy ingress / DNS target)"
  value       = hcloud_server.node[0].ipv4_address
}

output "wildcard" {
  description = "Wildcard hostname pointing at the ingress node (empty if no domain)"
  value       = (var.domain == "" || var.windows || var.dev) ? "" : "*.${var.domain}"
}

output "windows_host" {
  description = "windows.<domain> for a Windows node (empty otherwise)"
  value       = (var.domain != "" && var.windows) ? "windows.${var.domain}" : ""
}

output "dev_host" {
  description = "dev.<domain> for a dev node (or windows.<domain> for a dev-windows node; empty otherwise)"
  value       = var.dev ? (var.domain == "" ? "" : (var.windows ? "windows.${var.domain}" : "dev.${var.domain}")) : ""
}

output "dev_ssh_port" {
  description = "Host port the dev recipe publishes its in-container sshd on"
  value       = var.dev_ssh_port
}

output "domain" {
  value = var.domain
}

output "cluster_name" {
  value = var.cluster_name
}

output "server_type" {
  value = var.server_type
}

output "location" {
  value = var.location
}

output "ssh_private_key_file" {
  value = var.ssh_private_key_file
}
