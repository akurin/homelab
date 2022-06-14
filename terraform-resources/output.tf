output "node-0_ipv4_address" {
  value = vultr_instance.node-0.main_ip
}

output "vpn_ipv4_address" {
  value = vultr_instance.vpn.main_ip
}
