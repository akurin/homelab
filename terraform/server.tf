resource "hcloud_server" "node-0" {
  name        = "node-0"
  image       = var.os_type
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [hcloud_ssh_key.default.id]
  labels = {
    type = "kuber"
  }
}
