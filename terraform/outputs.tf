output "master_public_ips" {
  value = [hcloud_server.master.*.ipv4_address]
}

output "node_public_ips" {
  value = [hcloud_server.node.*.ipv4_address]
}

