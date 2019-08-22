#! /bin/bash

set -e

ENVIRONMENT=$(cat .environment)
HCLOUD_TOKEN=$(cat ~/.ssh/hcloud-$ENVIRONMENT-token)

if [ -z "$HCLOUD_TOKEN" ]
then
    echo "Couldn't find your hetzner cloud token in '~/.ssh/hcloud-$ENVIRONMENT-token'"
    exit 1
fi

echo $HCLOUD_TOKEN