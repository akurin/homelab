resource "vultr_instance" "headscale" {
  hostname    = "headscale-control-plane"
  label       = "headscale-control-plane"
  os_id       = var.os_id
  plan        = var.headscale_plan
  region      = var.region
  ssh_key_ids = [vultr_ssh_key.default.id]
}
