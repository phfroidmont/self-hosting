data "hcloud_image" "nixos_stable" {
  with_selector = "nixos=21.05"
}

data "hcloud_floating_ip" "main_ip" {
  with_selector = "external=main"
}

data "sops_file" "secrets" {
  source_file = "secrets.enc.yml"
}

resource "hcloud_network" "private_network" {
  name = "private"
  ip_range = "10.0.0.0/16"
}

resource "hcloud_network_subnet" "db_network_subnet" {
  type = "cloud"
  network_id = hcloud_network.private_network.id
  network_zone = "eu-central"
  ip_range = "10.0.1.0/24"
}

resource "hcloud_server" "db1" {
  name = "db1"
  image = data.hcloud_image.nixos_stable.id
  server_type = "cpx11"
  ssh_keys = [
    hcloud_ssh_key.phfroidmont-desktop.id
  ]
  keep_disk = true
  location = "hel1"

  network {
    network_id = hcloud_network.private_network.id
    ip = "10.0.1.11"
  }

  labels = {
    type = "db"
  }

  depends_on = [
    hcloud_network_subnet.db_network_subnet
  ]
}

module "deploy_nixos_db1" {
  source = "github.com/phfroidmont/terraform-nixos//deploy_nixos?ref=a8d5d31e59f4ce2677272e4849b122b4afc5a8e4"
  nixos_config = "db1"
  flake = true
  target_host = hcloud_server.db1.ipv4_address
  ssh_agent = true
  keys = {
    "postgres-init.sql" = <<-EOT
      CREATE ROLE "synapse" WITH LOGIN PASSWORD '${data.sops_file.secrets.data["synapse.db_password"]}';
      CREATE DATABASE "synapse" WITH OWNER "synapse"
        TEMPLATE template0
        LC_COLLATE = "C"
        LC_CTYPE = "C";
      EOT
    borgbackup-passphrase = data.sops_file.secrets.data["borg.passphrase"]
    borgbackup-ssh-key = data.sops_file.secrets.data["borg.client_keys.db1.private"]
  }
}

resource "hcloud_server" "backend1" {
  name = "backend1"
  image = data.hcloud_image.nixos_stable.id
  server_type = "cpx21"
  ssh_keys = [
    hcloud_ssh_key.phfroidmont-desktop.id
  ]
  keep_disk = true
  location = "hel1"

  network {
    network_id = hcloud_network.private_network.id
    ip = "10.0.1.1"
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
  server_id = hcloud_server.backend1.id
}

module "deploy_nixos_backend1" {
  source = "github.com/phfroidmont/terraform-nixos//deploy_nixos?ref=a8d5d31e59f4ce2677272e4849b122b4afc5a8e4"
  nixos_config = "backend1"
  flake = true
  target_host = hcloud_server.backend1.ipv4_address
  ssh_agent = true

  keys = {
    "synapse-extra-config.yaml" = <<-EOT
      database:
        name: psycopg2
        args:
          database: synapse
          host: "10.0.1.11"
          user: "synapse"
          password: "${data.sops_file.secrets.data["synapse.db_password"]}"
      macaroon_secret_key: "${data.sops_file.secrets.data["synapse.macaroon_secret_key"]}"
      EOT
    "murmur.env" = <<-EOT
      MURMURD_PASSWORD=${data.sops_file.secrets.data["murmur.password"]}
      EOT
    borgbackup-passphrase = data.sops_file.secrets.data["borg.passphrase"]
    borgbackup-ssh-key = data.sops_file.secrets.data["borg.client_keys.backend1.private"]
  }
}