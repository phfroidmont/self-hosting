output "loadbalancer_ip" {
  value = var.lb_ip
}

output "node_public_ips" {
  value = [scaleway_server.node.*.public_ip]
}

output "master_public_ips" {
  value = [scaleway_server.master.*.public_ip]
}
