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
  value       = var.domain == "" ? "" : "*.${var.domain}"
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
