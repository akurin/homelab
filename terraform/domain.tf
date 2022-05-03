resource "vultr_dns_domain" "my_domain" {
  domain = "morjoff.com"
  ip     = vultr_instance.node-0.main_ip
}
