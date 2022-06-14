resource "local_file" "inventory" {
  filename = "../ansible/inventory/hosts.yml"
  content = templatefile("inventory.tftpl", {
    node-0_ipv4_address = vultr_instance.node-0.main_ip
    vpn_ipv4_address    = vultr_instance.vpn.main_ip
  })
}
