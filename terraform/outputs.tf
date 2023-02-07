output "db1_public_ip" {
  value = hcloud_server.db1.ipv4_address
}

output "backend1_public_ip" {
  value = hcloud_server.backend1.ipv4_address
}
