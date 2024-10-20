resource "local_file" "inventory" {
  filename = "../ansible/inventory/vpn_vultr_hosts.yml"
  content  = templatefile("inventory.tftpl", {
    instances = { for k, v in vultr_instance.vpn : k => {
      hostname = v.hostname,
      main_ip  = v.main_ip
    }}
  })
  file_permission      = "0644"
  directory_permission = "0755"
}
