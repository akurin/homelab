resource "vultr_firewall_group" "k3s_node" {
  description = "base firewall"
}

resource "vultr_firewall_rule" "allow_tailscale" {
  firewall_group_id = vultr_firewall_group.k3s_node.id
  protocol          = "udp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "41641"
}

resource "vultr_firewall_rule" "allow_http" {
  firewall_group_id = vultr_firewall_group.k3s_node.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "80"
}

resource "vultr_firewall_rule" "allow_https" {
  firewall_group_id = vultr_firewall_group.k3s_node.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "443"
}

resource "vultr_firewall_rule" "allow_ssh" {
  firewall_group_id = vultr_firewall_group.k3s_node.id
  protocol          = "tcp"
  ip_type           = "v4"
  subnet            = "0.0.0.0"
  subnet_size       = 0
  port              = "22"
}

