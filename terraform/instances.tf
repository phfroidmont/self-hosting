resource "hcloud_server" "node" {
  count       = var.node_server_count
  name        = "node${count.index + 1}"
  image       = "ubuntu-18.04"
  server_type = var.node_server_type
  ssh_keys    = [hcloud_ssh_key.desktop.id]
  keep_disk   = true

  labels = {
    environment = local.environment
    type        = "node"
  }
}

resource "hcloud_server_network" "node_network" {
  count      = var.node_server_count
  server_id  = "${hcloud_server.node[count.index].id}"
  network_id = "${hcloud_network.private_network.id}"
  ip         = "192.168.2.${count.index + 1}"
}

resource "hcloud_server" "master" {
  count       = var.master_server_count
  name        = "master${count.index + 1}"
  image       = "ubuntu-18.04"
  server_type = var.master_server_type
  ssh_keys    = [hcloud_ssh_key.desktop.id]
  keep_disk   = true

  labels = {
    environment = local.environment
    type        = "master"
  }
}

resource "hcloud_server_network" "master_network" {
  count      = var.master_server_count
  server_id  = "${hcloud_server.master[count.index].id}"
  network_id = "${hcloud_network.private_network.id}"
  ip         = "192.168.1.${count.index + 1}"
}
