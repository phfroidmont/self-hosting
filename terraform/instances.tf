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
