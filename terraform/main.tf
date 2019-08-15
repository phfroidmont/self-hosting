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

provider "scaleway" {
  region = var.region
}

data "scaleway_image" "ubuntu" {
  architecture = var.architecture
  name         = var.image
}

resource "scaleway_server" "node" {
  count               = var.node_instance_count
  name                = "node${count.index + 1}"
  image               = data.scaleway_image.ubuntu.id
  type                = var.node_instance_type
  state               = "running"
  dynamic_ip_required = true
  tags                = ["${local.environment}-node"]
}

resource "scaleway_server" "master" {
  count               = var.master_instance_count
  name                = "master${count.index + 1}"
  image               = data.scaleway_image.ubuntu.id
  type                = var.master_instance_type
  state               = "running"
  dynamic_ip_required = true
  tags = [
    "${local.environment}-master",
    "${local.environment}-etcd",
  ]
}

output "node_private_ips" {
  value = [scaleway_server.node.*.private_ip]
}

output "master_private_ips" {
  value = [scaleway_server.master.*.private_ip]
}

