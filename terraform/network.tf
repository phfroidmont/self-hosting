resource "hcloud_network" "private_network" {
  name     = "private_network"
  ip_range = "192.168.0.0/16"

  labels = {
    environment = local.environment
  }
}

resource "hcloud_network_subnet" "master_network" {
  network_id   = "${hcloud_network.private_network.id}"
  type         = "server"
  network_zone = "eu-central"
  ip_range     = "192.168.1.0/24"
}

resource "hcloud_network_subnet" "node_network" {
  network_id   = "${hcloud_network.private_network.id}"
  type         = "server"
  network_zone = "eu-central"
  ip_range     = "192.168.2.0/24"
}
