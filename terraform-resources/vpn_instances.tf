resource "vultr_instance" "vpn" {
  for_each = toset(var.vpn_regions)

  hostname    = "${terraform.workspace}-vpn-${each.key}"
  label       = "${terraform.workspace}-vpn-${each.key}"
  os_id       = var.os_id
  plan        = var.vpn_server_plan
  region      = each.key
  ssh_key_ids = [vultr_ssh_key.default.id]
}
