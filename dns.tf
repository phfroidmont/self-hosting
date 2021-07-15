locals {
  dmarc_value = "\"v=DMARC1; p=none; rua=mailto:failed-dmarc@banditlair.com; ruf=mailto:dmarc@banditlair.com\""
  dkim_value = "\"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCwDEwt+a0neFlyq7ndCj0EECUp4bsusFpL2aVzroLY5Xw9S//dYuXUp1sr/yiivS71WyNjt7tOpuonu0gGEWpc6RPyeZrzXQg+zY1k/1+cLXFMz5HmJJaAbNxK02Qn89qfk/Y3pbuJt6Y/NBQ4KVOCZQB2hCT2izVSWSkhegYTCwIDAQAB\""
}

data "hetznerdns_zone" "banditlair_zone" {
  name = "banditlair.com"
}

resource "hetznerdns_record" "banditlair_hcloud_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "@"
  value = data.hcloud_floating_ip.main_ip.ip_address
  type = "A"
  ttl = 600
}

resource "hetznerdns_record" "banditlair_dedicated_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "*"
  value = "144.76.18.197"
  type = "A"
  ttl = 600
}

# Matrix
resource "hetznerdns_record" "matrix_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "matrix"
  value = data.hcloud_floating_ip.main_ip.ip_address
  type = "A"
  ttl = 600
}

resource "hetznerdns_record" "matrix_srv" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "_matrix._tcp"
  value = "12 10 443 matrix"
  type = "SRV"
  ttl = 86400
}

# Email
resource "hetznerdns_record" "mail_mx" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "@"
  value = "12 mail"
  type = "MX"
  ttl = 86400
}

resource "hetznerdns_record" "mail2_mx" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "@"
  value = "20 mail2"
  type = "MX"
  ttl = 86400
}

resource "hetznerdns_record" "spf_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "@"
  value = "\"v=spf1 mx -all\""
  type = "TXT"
  ttl = 600
}

resource "hetznerdns_record" "dmarc_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "_dmarc"
  value = local.dmarc_value
  type = "TXT"
  ttl = 600
}

resource "hetznerdns_record" "dmarc_report_froidmont_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "froidmont.org._report._dmarc"
  value = "\"v=DMARC1\""
  type = "TXT"
  ttl = 600
}

resource "hetznerdns_record" "dmarc_report_falbo_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "falbo.fr._report._dmarc"
  value = "\"v=DMARC1\""
  type = "TXT"
  ttl = 600
}

resource "hetznerdns_record" "dkim_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name = "dkim._domainkey"
  value = local.dkim_value
  type = "TXT"
  ttl = 600
}

data "hetznerdns_zone" "falbo_zone" {
  name = "falbo.fr"
}

resource "hetznerdns_record" "falbo_a" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name = "@"
  value = hetznerdns_record.banditlair_dedicated_a.value
  type = "A"
  ttl = 600
}

resource "hetznerdns_record" "falbo_cname" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name = "*"
  value = "${data.hetznerdns_zone.falbo_zone.name}."
  type = "CNAME"
  ttl = 600
}

resource "hetznerdns_record" "falbo_mail_mx" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name = "@"
  value = "12 mail.${data.hetznerdns_zone.banditlair_zone.name}."
  type = "MX"
  ttl = 86400
}

resource "hetznerdns_record" "falbo_mail2_mx" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name = "@"
  value = "20 mail2.${data.hetznerdns_zone.banditlair_zone.name}."
  type = "MX"
  ttl = 86400
}

resource "hetznerdns_record" "falbo_spf_txt" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name = "@"
  value = "\"v=spf1 include:${data.hetznerdns_zone.banditlair_zone.name} -all\""
  type = "TXT"
  ttl = 600
}

resource "hetznerdns_record" "falbo_dmarc_txt" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name = "_dmarc"
  value = local.dmarc_value
  type = "TXT"
  ttl = 600
}

resource "hetznerdns_record" "falbo_dkim_txt" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name = "dkim._domainkey"
  value = local.dkim_value
  type = "TXT"
  ttl = 600
}

data "hetznerdns_zone" "froidmont_zone" {
  name = "froidmont.org"
}

resource "hetznerdns_record" "froidmont_a" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name = "@"
  value = hetznerdns_record.banditlair_dedicated_a.value
  type = "A"
  ttl = 600
}

resource "hetznerdns_record" "froidmont_cname" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name = "*"
  value = "${data.hetznerdns_zone.froidmont_zone.name}."
  type = "CNAME"
  ttl = 600
}

resource "hetznerdns_record" "froidmont_mail_mx" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name = "@"
  value = "12 mail.${data.hetznerdns_zone.banditlair_zone.name}."
  type = "MX"
  ttl = 86400
}

resource "hetznerdns_record" "froidmont_mail2_mx" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name = "@"
  value = "20 mail2.${data.hetznerdns_zone.banditlair_zone.name}."
  type = "MX"
  ttl = 86400
}

resource "hetznerdns_record" "froidmont_spf_txt" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name = "@"
  value = "\"v=spf1 include:${data.hetznerdns_zone.banditlair_zone.name} -all\""
  type = "TXT"
  ttl = 600
}

resource "hetznerdns_record" "froidmont_dmarc_txt" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name = "_dmarc"
  value = local.dmarc_value
  type = "TXT"
  ttl = 600
}

resource "hetznerdns_record" "froidmont_dkim_txt" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name = "dkim._domainkey"
  value = local.dkim_value
  type = "TXT"
  ttl = 600
}

data "hetznerdns_zone" "stb_zone" {
  name = "societe-de-tir-bertrix.com"
}

resource "hetznerdns_record" "stb_a" {
  zone_id = data.hetznerdns_zone.stb_zone.id
  name = "@"
  value = hetznerdns_record.banditlair_dedicated_a.value
  type = "A"
  ttl = 600
}

resource "hetznerdns_record" "stb_cname" {
  zone_id = data.hetznerdns_zone.stb_zone.id
  name = "*"
  value = "${data.hetznerdns_zone.stb_zone.name}."
  type = "CNAME"
  ttl = 600
}