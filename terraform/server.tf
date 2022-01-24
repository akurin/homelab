resource "vultr_instance" "node-0" {
  label       = "node-0"
  os_id       = var.os_id
  plan        = var.plan
  region      = var.region
  ssh_key_ids = [vultr_ssh_key.default.id]
}
