locals {
  dmarc_value   = "\"v=DMARC1; p=none; rua=mailto:failed-dmarc@banditlair.com; ruf=mailto:dmarc@banditlair.com\""
  hel1_ip   = "37.27.138.62"
  hel1_ipv6 = "2a01:4f9:3100:1202::2"
}

data "hetznerdns_zone" "banditlair_zone" {
  name = "banditlair.com"
}

data "hetznerdns_zone" "froidmont_solutions_zone" {
  name = "froidmont.solutions"
}

resource "hetznerdns_record" "banditlair_hcloud_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "@"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "webmail_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "webmail"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "mail_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "mail"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "mail_aaaa" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "mail"
  value   = local.hel1_ipv6
  type    = "AAAA"
  ttl     = 600
}

resource "hetznerdns_record" "hel1_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "hel1"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "grafana_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "grafana"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "jellyfin_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "jellyfin"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "status_banditlair_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "status"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "jitsi_a" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "jitsi"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "uptime_a" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "uptime"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "transmission_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "transmission"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "jackett_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "jackett"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "sonarr_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "sonarr"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "radarr_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "radarr"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "lidarr_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "lidarr"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "vtt_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "vtt"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "photos_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "photos"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "monero_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "monero"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "anderia_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "anderia"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "arkadia_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "arkadia"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "cifirpg_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "scifirpg"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "banditlair_dedicated_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "*"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "nextcloud_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "cloud"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

# Matrix
resource "hetznerdns_record" "matrix_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "matrix"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "matrix_srv" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "_matrix._tcp"
  value   = "12 10 443 matrix"
  type    = "SRV"
  ttl     = 86400
}

resource "hetznerdns_record" "coturn_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "turn"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "ch_a" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "ch"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

# Email
resource "hetznerdns_record" "mail_mx" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "@"
  value   = "12 mail"
  type    = "MX"
  ttl     = 86400
}

resource "hetznerdns_record" "spf_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "@"
  value   = "\"v=spf1 mx -all\""
  type    = "TXT"
  ttl     = 600
}

resource "hetznerdns_record" "dmarc_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "_dmarc"
  value   = local.dmarc_value
  type    = "TXT"
  ttl     = 600
}

resource "hetznerdns_record" "dmarc_report_froidmont_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "froidmont.org._report._dmarc"
  value   = "\"v=DMARC1\""
  type    = "TXT"
  ttl     = 600
}

resource "hetznerdns_record" "dmarc_report_falbo_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "falbo.fr._report._dmarc"
  value   = "\"v=DMARC1\""
  type    = "TXT"
  ttl     = 600
}

resource "hetznerdns_record" "dkim_txt" {
  zone_id = data.hetznerdns_zone.banditlair_zone.id
  name    = "mail._domainkey"
  value   = "\"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCgRhQ9zN4hkiASKH4kTfWUSBz+Ov7BvH0459BDVeSNQFjH3KjmofJicKQ6eWXGJOSz4jCpNDRdgMbkVHEiTHOcKd/u9LqxEchWKZU50lwSrYhUmr8j+b4vgf+sUxIWKCZUNuyrDp2ROeheA3Pbx+fYJb3VhGTZecLlchMrRjBJqwIDAQAB\""
  type    = "TXT"
  ttl     = 600
}

data "hetznerdns_zone" "falbo_zone" {
  name = "falbo.fr"
}

resource "hetznerdns_record" "falbo_a" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name    = "@"
  value   = hetznerdns_record.banditlair_dedicated_a.value
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "falbo_cname" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name    = "*"
  value   = "${data.hetznerdns_zone.falbo_zone.name}."
  type    = "CNAME"
  ttl     = 600
}

resource "hetznerdns_record" "falbo_mail_mx" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name    = "@"
  value   = "12 mail.${data.hetznerdns_zone.banditlair_zone.name}."
  type    = "MX"
  ttl     = 86400
}

resource "hetznerdns_record" "falbo_spf_txt" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name    = "@"
  value   = "\"v=spf1 include:${data.hetznerdns_zone.banditlair_zone.name} -all\""
  type    = "TXT"
  ttl     = 600
}

resource "hetznerdns_record" "falbo_dmarc_txt" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name    = "_dmarc"
  value   = local.dmarc_value
  type    = "TXT"
  ttl     = 600
}

resource "hetznerdns_record" "falbo_dkim_txt" {
  zone_id = data.hetznerdns_zone.falbo_zone.id
  name    = "mail._domainkey"
  value   = "\"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCY6ESTQcWbZVNxjb8TFhpyhCoG6Ri8OV1MijDHGNmpLye8AsuMzaEdcFk59AoIWPI6P9ZGIXzYTTwRxXhCIBrRJgcDGrbTAQ7tuaKggJRCXhan7FVMizZSJ53NEr3f4PFaBtrV0Ni8f7ENuT6WcQQ+JsMN3vEGbwA1LmgHH2XSBQIDAQAB\""
  type    = "TXT"
  ttl     = 600
}

data "hetznerdns_zone" "froidmont_zone" {
  name = "froidmont.org"
}

resource "hetznerdns_record" "froidmont_a" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "@"
  value   = hetznerdns_record.banditlair_dedicated_a.value
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "website_marie_a" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "osteopathie"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "forge_a" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "forge"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "froidmont_cname" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "*"
  value   = "${data.hetznerdns_zone.froidmont_zone.name}."
  type    = "CNAME"
  ttl     = 600
}

resource "hetznerdns_record" "froidmont_mail_mx" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "@"
  value   = "12 mail.${data.hetznerdns_zone.banditlair_zone.name}."
  type    = "MX"
  ttl     = 86400
}

resource "hetznerdns_record" "froidmont_spf_txt" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "@"
  value   = "\"v=spf1 include:${data.hetznerdns_zone.banditlair_zone.name} -all\""
  type    = "TXT"
  ttl     = 600
}

resource "hetznerdns_record" "froidmont_dmarc_txt" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "_dmarc"
  value   = local.dmarc_value
  type    = "TXT"
  ttl     = 600
}

resource "hetznerdns_record" "froidmont_dkim_txt" {
  zone_id = data.hetznerdns_zone.froidmont_zone.id
  name    = "mail._domainkey"
  value   = "\"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDoY56+gnsfCFGVchumtl7mnRuFENBKoTojxpMZQ8kHPY68pkTg7Xw0M6GtfLQQa/2VGCddQIYcXH74nu7J/4vakEPLp7JYsToqbLOucfXoFbBAQN3N43YyUsp8DqMh80y0UjItHf04HQUfa+OyjJWZD9JZm2oKIAO4Z0X0RoSyWwIDAQAB\""
  type    = "TXT"
  ttl     = 600
}

data "hetznerdns_zone" "stb_zone" {
  name = "societe-de-tir-bertrix.com"
}

resource "hetznerdns_record" "stb_a" {
  zone_id = data.hetznerdns_zone.stb_zone.id
  name    = "@"
  value   = local.hel1_ip
  type    = "A"
  ttl     = 600
}

resource "hetznerdns_record" "stb_cname" {
  zone_id = data.hetznerdns_zone.stb_zone.id
  name    = "*"
  value   = "${data.hetznerdns_zone.stb_zone.name}."
  type    = "CNAME"
  ttl     = 600
}
