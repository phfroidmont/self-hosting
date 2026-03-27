locals {
  dmarc_value = "\"v=DMARC1; p=none; rua=mailto:failed-dmarc@banditlair.com; ruf=mailto:dmarc@banditlair.com\""
  hel1_ip     = "37.27.138.62"
  hel1_ipv6   = "2a01:4f9:3100:1202::2"
}

data "hcloud_zone" "banditlair_zone" {
  name = "banditlair.com"
}

resource "hcloud_zone_rrset" "banditlair_hcloud_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "@"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "banditlair_mcmap_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "mcmap"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "webmail_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "webmail"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "mail_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "mail"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "mail_aaaa" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "mail"
  records = [{ value = local.hel1_ipv6 }]
  type    = "AAAA"
}

resource "hcloud_zone_rrset" "hel1_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "hel1"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "ws_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "ws"
  records = [{ value = hcloud_server.relay1.ipv4_address }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "grafana_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "grafana"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "jellyfin_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "jellyfin"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "status_banditlair_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "status"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "jitsi_a" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "jitsi"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "uptime_a" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "uptime"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "transmission_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "transmission"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "jackett_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "jackett"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "sonarr_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "sonarr"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "radarr_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "radarr"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "lidarr_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "lidarr"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "slskd_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "slskd"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "vtt_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "vtt"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "photos_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "photos"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "monero_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "monero"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "anderia_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "anderia"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "arkadia_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "arkadia"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "chroniques_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "chroniques"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "cifirpg_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "scifirpg"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "banditlair_dedicated_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "*"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "nextcloud_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "cloud"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

# Matrix
resource "hcloud_zone_rrset" "matrix_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "matrix"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "matrix_srv" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "_matrix._tcp"
  records = [{ value = "12 10 443 matrix.banditlair.com." }]
  type    = "SRV"
}

resource "hcloud_zone_rrset" "coturn_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "turn"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "ch_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "ch"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "hs_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "hs"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

# Email
resource "hcloud_zone_rrset" "mail_mx" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "@"
  records = [{ value = "12 mail.banditlair.com." }]
  type    = "MX"
}

resource "hcloud_zone_rrset" "spf_txt" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "@"
  records = [{ value = "\"v=spf1 mx -all\"" }]
  type    = "TXT"
  ttl     = 600
}

resource "hcloud_zone_rrset" "dmarc_txt" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "_dmarc"
  records = [{ value = local.dmarc_value }]
  type    = "TXT"
  ttl     = 600
}

resource "hcloud_zone_rrset" "dmarc_report_froidmont_txt" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "froidmont.org._report._dmarc"
  records = [{ value = "\"v=DMARC1\"" }]
  type    = "TXT"
  ttl     = 600
}

resource "hcloud_zone_rrset" "dmarc_report_falbo_txt" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "falbo.fr._report._dmarc"
  records = [{ value = "\"v=DMARC1\"" }]
  type    = "TXT"
  ttl     = 600
}

resource "hcloud_zone_rrset" "dkim_txt" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "mail._domainkey"
  records = [{ value = "\"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCgRhQ9zN4hkiASKH4kTfWUSBz+Ov7BvH0459BDVeSNQFjH3KjmofJicKQ6eWXGJOSz4jCpNDRdgMbkVHEiTHOcKd/u9LqxEchWKZU50lwSrYhUmr8j+b4vgf+sUxIWKCZUNuyrDp2ROeheA3Pbx+fYJb3VhGTZecLlchMrRjBJqwIDAQAB\"" }]
  type    = "TXT"
  ttl     = 600
}

data "hcloud_zone" "falbo_zone" {
  name = "falbo.fr"
}

resource "hcloud_zone_rrset" "falbo_a" {
  zone    = data.hcloud_zone.falbo_zone.name
  name    = "@"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "falbo_cname" {
  zone    = data.hcloud_zone.falbo_zone.name
  name    = "*"
  records = [{ value = "${data.hcloud_zone.falbo_zone.name}." }]
  type    = "CNAME"
  ttl     = 600
}

resource "hcloud_zone_rrset" "falbo_mail_mx" {
  zone    = data.hcloud_zone.falbo_zone.name
  name    = "@"
  records = [{ value = "12 mail.${data.hcloud_zone.banditlair_zone.name}." }]
  type    = "MX"
}

resource "hcloud_zone_rrset" "falbo_spf_txt" {
  zone    = data.hcloud_zone.falbo_zone.name
  name    = "@"
  records = [{ value = "\"v=spf1 include:${data.hcloud_zone.banditlair_zone.name} -all\"" }]
  type    = "TXT"
  ttl     = 600
}

resource "hcloud_zone_rrset" "falbo_dmarc_txt" {
  zone    = data.hcloud_zone.falbo_zone.name
  name    = "_dmarc"
  records = [{ value = local.dmarc_value }]
  type    = "TXT"
  ttl     = 600
}

resource "hcloud_zone_rrset" "falbo_dkim_txt" {
  zone    = data.hcloud_zone.falbo_zone.name
  name    = "mail._domainkey"
  records = [{ value = "\"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCY6ESTQcWbZVNxjb8TFhpyhCoG6Ri8OV1MijDHGNmpLye8AsuMzaEdcFk59AoIWPI6P9ZGIXzYTTwRxXhCIBrRJgcDGrbTAQ7tuaKggJRCXhan7FVMizZSJ53NEr3f4PFaBtrV0Ni8f7ENuT6WcQQ+JsMN3vEGbwA1LmgHH2XSBQIDAQAB\"" }]
  type    = "TXT"
  ttl     = 600
}

data "hcloud_zone" "froidmont_zone" {
  name = "froidmont.org"
}

resource "hcloud_zone_rrset" "froidmont_a" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "@"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "rl_a" {
  zone    = data.hcloud_zone.banditlair_zone.name
  name    = "rl"
  records = [{ value = hcloud_server.relay1.ipv4_address }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "website_marie_a" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "osteopathie"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "forge_a" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "forge"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "froidmont_cname" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "*"
  records = [{ value = "${data.hcloud_zone.froidmont_zone.name}." }]
  type    = "CNAME"
  ttl     = 600
}

resource "hcloud_zone_rrset" "froidmont_mail_mx" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "@"
  records = [{ value = "12 mail.${data.hcloud_zone.banditlair_zone.name}." }]
  type    = "MX"
}

resource "hcloud_zone_rrset" "froidmont_spf_txt" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "@"
  records = [{ value = "\"v=spf1 include:${data.hcloud_zone.banditlair_zone.name} -all\"" }]
  type    = "TXT"
  ttl     = 600
}

resource "hcloud_zone_rrset" "froidmont_dmarc_txt" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "_dmarc"
  records = [{ value = local.dmarc_value }]
  type    = "TXT"
  ttl     = 600
}

resource "hcloud_zone_rrset" "froidmont_dkim_txt" {
  zone    = data.hcloud_zone.froidmont_zone.name
  name    = "mail._domainkey"
  records = [{ value = "\"v=DKIM1; k=rsa; p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDoY56+gnsfCFGVchumtl7mnRuFENBKoTojxpMZQ8kHPY68pkTg7Xw0M6GtfLQQa/2VGCddQIYcXH74nu7J/4vakEPLp7JYsToqbLOucfXoFbBAQN3N43YyUsp8DqMh80y0UjItHf04HQUfa+OyjJWZD9JZm2oKIAO4Z0X0RoSyWwIDAQAB\"" }]
  type    = "TXT"
  ttl     = 600
}

data "hcloud_zone" "stb_zone" {
  name = "societe-de-tir-bertrix.com"
}

resource "hcloud_zone_rrset" "stb_a" {
  zone    = data.hcloud_zone.stb_zone.name
  name    = "@"
  records = [{ value = local.hel1_ip }]
  type    = "A"
  ttl     = 600
}

resource "hcloud_zone_rrset" "stb_cname" {
  zone    = data.hcloud_zone.stb_zone.name
  name    = "*"
  records = [{ value = "${data.hcloud_zone.stb_zone.name}." }]
  type    = "CNAME"
  ttl     = 600
}
