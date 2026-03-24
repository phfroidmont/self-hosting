provider "hcloud" {}

resource "hcloud_ssh_key" "phfroidmont_stellaris" {
  name       = "phfroidmont-stellaris"
  public_key = file("${path.module}/../ssh_keys/phfroidmont-stellaris.pub")
}

resource "hcloud_ssh_key" "froidmpa_desktop" {
  name       = "froidmpa-desktop"
  public_key = file("${path.module}/../ssh_keys/froidmpa-desktop.pub")
}

resource "hcloud_ssh_key" "elios_desktop" {
  name       = "elios-desktop"
  public_key = file("${path.module}/../ssh_keys/elios-desktop.pub")
}

resource "hcloud_server" "relay1" {
  name        = "relay1"
  server_type = "cx23"
  image       = "ubuntu-24.04"
  location    = "nbg1"

  public_net {
    ipv4_enabled = true
    ipv6_enabled = false
  }

  ssh_keys = [
    hcloud_ssh_key.phfroidmont_stellaris.id,
    hcloud_ssh_key.froidmpa_desktop.id,
    hcloud_ssh_key.elios_desktop.id,
  ]
}

module "nixos_anywhere_install" {
  source = "github.com/nix-community/nixos-anywhere//terraform/install"

  target_host = hcloud_server.relay1.ipv4_address
  instance_id = hcloud_server.relay1.id
  flake       = "${path.module}/..#relay1"

  depends_on = [hcloud_server.relay1]
}
