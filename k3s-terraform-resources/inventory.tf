resource "local_file" "inventory" {
  filename = "../ansible/inventory/${terraform.workspace}_hosts.yml"
  content = templatefile("inventory.tftpl", {
    server_instances = vultr_instance.k3s_server[*]
    agent_instances  = vultr_instance.k3s_agent[*]
  })
  file_permission      = "0644"
  directory_permission = "0755"
}
