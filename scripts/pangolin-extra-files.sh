#!/usr/bin/env bash
set -euo pipefail
umask 077

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# nixos-anywhere runs this in the temporary root overlay directory.
install -d -m 0755 etc/ssh
sops --decrypt --extract '["bootstrap"]["ssh_host_rsa_key"]' \
  "$repo_root/secrets/pangolin.enc.yml" > etc/ssh/ssh_host_rsa_key
ssh-keygen -y -f etc/ssh/ssh_host_rsa_key > etc/ssh/ssh_host_rsa_key.pub
chmod 0644 etc/ssh/ssh_host_rsa_key.pub
