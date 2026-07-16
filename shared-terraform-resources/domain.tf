resource "vultr_dns_domain" "my_domain" {
  domain = "morjoff.com"
}

resource "vultr_dns_record" "wildcard" {
  domain = vultr_dns_domain.my_domain.domain
  name   = "*"
  type   = "A"
  data   = "209.250.225.251"
  ttl    = 300
}

resource "vultr_dns_record" "fallback" {
  domain = vultr_dns_domain.my_domain.domain
  name   = ""
  type   = "A"
  data   = "209.250.225.251"
  ttl    = 300
}

resource "vultr_dns_record" "mx" {
  domain = vultr_dns_domain.my_domain.domain
  name   = ""
  type   = "MX"
  data   = vultr_dns_domain.my_domain.domain
  ttl    = 300
}

resource "vultr_dns_record" "yagate" {
  domain = vultr_dns_domain.my_domain.domain
  name   = "yagate"
  type   = "CNAME"
  data   = "9a802493be3c1b96.topology.gslb.yccdn.ru"
  ttl    = 60
}

resource "vultr_dns_record" "yagate_acme_challenge" {
  domain = vultr_dns_domain.my_domain.domain
  name   = "_acme-challenge.yagate"
  type   = "CNAME"
  data   = "fpqtav3q97fdhmfc7cgr.cm.yandexcloud.net"
  ttl    = 60
}

resource "vultr_dns_record" "headscale" {
  domain = vultr_dns_domain.my_domain.domain
  name   = "headscale"
  type   = "A"
  data   = "193.181.211.150"
  ttl    = 300
}

resource "vultr_dns_record" "nl1" {
  domain = vultr_dns_domain.my_domain.domain
  name   = "nl1"
  type   = "A"
  data   = "89.124.104.67"
  ttl    = 300
}
