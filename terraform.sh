#! /bin/bash

set -e

export HCLOUD_TOKEN=$(./get_hcloud_token.sh)
ENVIRONMENT=$(cat .environment)

cd terraform

terraform workspace select $ENVIRONMENT
terraform "$@"

