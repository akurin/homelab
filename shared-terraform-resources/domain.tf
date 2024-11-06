resource "vultr_dns_domain" "my_domain" {
  domain = "morjoff.com"
}

resource "vultr_dns_record" "wildcard" {
  domain = vultr_dns_domain.my_domain.domain
  name   = "*"
  type   = "CNAME"
  data   = vultr_dns_domain.my_domain.domain
  ttl    = 300
}

resource "vultr_dns_record" "headscale" {
  domain = vultr_dns_domain.my_domain.domain
  name   = "headscale"
  type   = "A"
  data   = vultr_instance.headscale.main_ip
  ttl    = 300
}

resource "vultr_dns_record" "mx" {
  domain = vultr_dns_domain.my_domain.domain
  name   = ""
  type   = "MX"
  data   = vultr_dns_domain.my_domain.domain
  ttl    = 300
}
