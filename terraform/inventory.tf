resource "local_file" "inventory" {
  filename = "../ansible/inventory/hosts.yml"
  content  = templatefile("inventory.tftpl", { node-0_ipv4_address = hcloud_server.node-0.ipv4_address })
}
