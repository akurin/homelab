resource "vultr_dns_record" "wildcard" {
  domain = "morjoff.com"
  name   = "morjoff.com"
  type   = "A"
  data   = vultr_instance.k3s_server[0].main_ip
  ttl    = 300
}
