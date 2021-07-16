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

resource "hcloud_network_subnet" "banditlair_vswitch_network_subnet" {
  type = "vswitch"
  network_id = hcloud_network.private_network.id
  network_zone = "eu-central"
  ip_range = "10.0.2.0/24"
  vswitch_id = 22304
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
  source = "github.com/phfroidmont/terraform-nixos//deploy_nixos?ref=5f6b38f7e1485d216c14c3cbd6692581e5eaa392"
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
      CREATE ROLE "nextcloud" WITH LOGIN PASSWORD '${data.sops_file.secrets.data["nextcloud.db_password"]}';
      CREATE DATABASE "nextcloud" WITH OWNER "nextcloud";
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
  source = "github.com/phfroidmont/terraform-nixos//deploy_nixos?ref=5f6b38f7e1485d216c14c3cbd6692581e5eaa392"
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
    nextcloud-db-pass = data.sops_file.secrets.data["nextcloud.db_password"]
    nextcloud-admin-pass = data.sops_file.secrets.data["nextcloud.admin_password"]
    "murmur.env" = <<-EOT
      MURMURD_PASSWORD=${data.sops_file.secrets.data["murmur.password"]}
      EOT
    borgbackup-passphrase = data.sops_file.secrets.data["borg.passphrase"]
    borgbackup-ssh-key = data.sops_file.secrets.data["borg.client_keys.backend1.private"]
    sshfs-ssh-key = data.sops_file.secrets.data["sshfs_keys.private"]
  }
}