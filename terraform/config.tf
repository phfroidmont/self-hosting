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


provider "hetznerdns" {
  apitoken = data.sops_file.secrets.data["hcloud.dns_token"]
}

