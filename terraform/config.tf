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
      version = "~> 1.60"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
