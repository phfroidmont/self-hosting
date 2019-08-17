resource "null_resource" "load_balancer" {
  provisioner "local-exec" {
    command = "./scripts/create_lb.sh lb-k8s-${local.environment} ${var.lb_ip}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "./scripts/delete_lb.sh ${var.lb_ip}"
  }
}

resource "null_resource" "update_load_balancer_rules" {
  triggers = {
    node_instance_ids = "${join(",", scaleway_server.node.*.private_ip)}"
  }

  provisioner "local-exec" {
    command = "./scripts/update_lb_rules.sh ${var.lb_ip} '${jsonencode(scaleway_server.node.*.private_ip)}'"
  }

  depends_on = [null_resource.load_balancer]
}
