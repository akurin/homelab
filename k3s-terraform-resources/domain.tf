resource "vultr_dns_domain" "my_domain" {
  count  = terraform.workspace == "prod" ? 1 : 0
  domain = "morjoff.com"
  ip     = vultr_instance.k3s_server[0].main_ip
}
