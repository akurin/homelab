resource "local_file" "inventory" {
  filename = "../ansible/inventory/shared_hosts.yml"
  content = templatefile("inventory.tftpl", {
    headscale_instance = vultr_instance.headscale
  })
  file_permission      = "0644"
  directory_permission = "0755"
}
