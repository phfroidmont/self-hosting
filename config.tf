terraform {
  backend "http" {
  }
  required_providers {
    hcloud = {
      source = "hetznercloud/hcloud"
      version = "1.24.1"
    }

    hetznerdns = {
      source  = "timohirt/hetznerdns"
      version = ">= 1.1.1"
    }

    sops = {
      source = "carlpett/sops"
      version = "~> 0.5"
    }
  }
}

variable "hcloud_token" {}

provider "hcloud" {
  token = var.hcloud_token
}

resource "hcloud_ssh_key" "phfroidmont-desktop" {
  name = "phfroidmont-desktop"
  public_key = file("ssh_keys/phfroidmont-desktop.pub")
}

variable "hetznerdns_token" {}

provider "hetznerdns" {
  apitoken = var.hetznerdns_token
}
