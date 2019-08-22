#! /bin/bash

set -e

export HCLOUD_TOKEN=$(./get_hcloud_token.sh)
ENVIRONMENT=$(cat .environment)
source .virtualenv/bin/activate

ansible-playbook -i inventories/$ENVIRONMENT --vault-id=~/.ssh/vault-pass  "$@"
