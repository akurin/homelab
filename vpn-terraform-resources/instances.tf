resource "vultr_instance" "vpn" {
  for_each = toset(var.regions)

  hostname    = "vpn-${each.key}"
  label       = "vpn-${each.key}"
  os_id       = var.os_id
  plan        = var.server_plan
  region      = each.key
  ssh_key_ids = [vultr_ssh_key.default.id]
}
