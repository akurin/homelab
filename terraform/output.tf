output "ipv4_address" {
  value = hcloud_server.node-1[*].ipv4_address
}
