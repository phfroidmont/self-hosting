provider "scaleway" {
  region = "${var.region}"
}

data "scaleway_image" "ubuntu" {
  architecture = "${var.architecture}"
  name         = "${var.image}"
}

//resource "scaleway_ip" "public_ip" {
//  count = 1
//}

resource "scaleway_server" "node" {
  count  = "${var.node_instance_count}"
  name   = "node${count.index+1}"
  image  = "${data.scaleway_image.ubuntu.id}"
  type   = "${var.node_instance_type}"
  state  = "running"
  dynamic_ip_required = true,
  tags   = ["k8s", "kube-node"]
}

resource "scaleway_server" "master" {
  count  = "${var.master_instance_count}"
  name   = "master${count.index+1}"
  image  = "${data.scaleway_image.ubuntu.id}"
  type   = "${var.master_instance_type}"
  state  = "running"
  dynamic_ip_required = true,
  tags   = ["k8s", "kube-master","etcd"]
}

output "node_private_ips" {
  value = ["${scaleway_server.node.*.private_ip}"]
}

output "master_private_ips" {
  value = ["${scaleway_server.master.*.private_ip}"]
}

