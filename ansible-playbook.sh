#! /bin/bash

set -e

export HCLOUD_TOKEN=$(./get_hcloud_token.sh)
ENVIRONMENT=$(cat .environment)
source .virtualenv/bin/activate

ARGS="-i inventories/$ENVIRONMENT"
ARGS="$ARGS --vault-id=~/.ssh/vault-pass"
ARGS="$ARGS $@"

echo "ansible-playbook $ARGS"
ansible-playbook $ARGS
