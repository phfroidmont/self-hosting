terraform {
  backend "http" {
    address        = "https://gitlab.com/api/v4/projects/22845244/terraform/state/prod"
    lock_address   = "https://gitlab.com/api/v4/projects/22845244/terraform/state/prod/lock"
    lock_method    = "POST"
    unlock_address = "https://gitlab.com/api/v4/projects/22845244/terraform/state/prod/lock"
    unlock_method  = "DELETE"
    username       = "phfroidmont"
  }
  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "1.24.1"
    }

    hetznerdns = {
      source  = "timohirt/hetznerdns"
      version = ">= 2.2.0"
    }

    sops = {
      source  = "carlpett/sops"
      version = "~> 0.7"
    }
  }
}

data "sops_file" "secrets" {
  source_file = "../secrets.enc.yml"
}


provider "hcloud" {
  token = data.sops_file.secrets.data["hcloud.token"]
}

provider "hetznerdns" {
  apitoken = data.sops_file.secrets.data["hcloud.dns_token"]
}

resource "hcloud_ssh_key" "froidmpa-desktop" {
  name       = "froidmpa-desktop"
  public_key = file("../ssh_keys/froidmpa-desktop.pub")
}

resource "hcloud_ssh_key" "froidmpa-laptop" {
  name       = "froidmpa-laptop"
  public_key = file("../ssh_keys/froidmpa-laptop.pub")
}
