locals {
  environment = terraform.workspace != "" ? terraform.workspace : "test"
}

terraform {
  backend "s3" {
    bucket                      = "banditlair-k8s-tfstate"
    key                         = "banditlair.tfstate"
    region                      = "nl-ams"
    endpoint                    = "https://s3.nl-ams.scw.cloud"
    profile                     = "default"
    skip_credentials_validation = true
    skip_region_validation      = true
  }
}

provider "hcloud" {
}

resource "hcloud_ssh_key" "desktop" {
  name = "Desktop"
  public_key = "${file("ssh_keys/desktop.pub")}"
}
