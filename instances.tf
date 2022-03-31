data "hcloud_image" "nixos_stable" {
  with_selector = "nixos=21.05"
}

data "hcloud_floating_ip" "main_ip" {
  with_selector = "external=main"
}

resource "hcloud_network" "private_network" {
  name     = "private"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "db_network_subnet" {
  type         = "cloud"
  network_id   = hcloud_network.private_network.id
  network_zone = "eu-central"
  ip_range     = "10.0.1.0/24"
}

resource "hcloud_network_subnet" "banditlair_vswitch_network_subnet" {
  type         = "vswitch"
  network_id   = hcloud_network.private_network.id
  network_zone = "eu-central"
  ip_range     = "10.0.2.0/24"
  vswitch_id   = 29224
}

resource "hcloud_server" "db1" {
  name        = "db1"
  image       = data.hcloud_image.nixos_stable.id
  server_type = "cpx11"
  ssh_keys = [
    hcloud_ssh_key.phfroidmont-desktop.id
  ]
  keep_disk = true
  location  = "hel1"

  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.11"
  }

  labels = {
    type = "db"
  }

  depends_on = [
    hcloud_network_subnet.db_network_subnet
  ]
}

resource "hcloud_server" "backend1" {
  name        = "backend1"
  image       = data.hcloud_image.nixos_stable.id
  server_type = "cpx21"
  ssh_keys = [
    hcloud_ssh_key.phfroidmont-desktop.id
  ]
  keep_disk = true
  location  = "hel1"

  network {
    network_id = hcloud_network.private_network.id
    ip         = "10.0.1.1"
  }

  labels = {
    type = "backend"
  }

  depends_on = [
    hcloud_network_subnet.db_network_subnet
  ]
}

resource "hcloud_floating_ip_assignment" "main" {
  floating_ip_id = data.hcloud_floating_ip.main_ip.id
  server_id      = hcloud_server.backend1.id
}

