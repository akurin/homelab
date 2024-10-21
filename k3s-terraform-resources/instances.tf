resource "vultr_instance" "k3s_server" {
  count             = 1
  hostname          = "${terraform.workspace}-k3s-server-${count.index}"
  label             = "${terraform.workspace}-k3s-server-${count.index}"
  os_id             = var.os_id
  plan              = var.server_plan
  region            = var.region
  ssh_key_ids       = [vultr_ssh_key.default.id]
  firewall_group_id = vultr_firewall_group.k3s_node.id
}

resource "vultr_instance" "k3s_agent" {
  count             = 1
  hostname          = "${terraform.workspace}-k3s-agent-${count.index}"
  label             = "${terraform.workspace}-k3s-agent-${count.index}"
  os_id             = var.os_id
  plan              = var.agent_plan
  region            = var.region
  ssh_key_ids       = [vultr_ssh_key.default.id]
  firewall_group_id = vultr_firewall_group.k3s_node.id
}

