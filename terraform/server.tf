resource "hcloud_server" "node-1" {
  count       = var.instances
  name        = "node-${count.index}"
  image       = var.os_type
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.default.id]
  labels = {
    type = "kuber"
  }
}