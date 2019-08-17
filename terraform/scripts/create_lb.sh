#!/bin/bash

set -e
set -x

export TOKEN=`jq '.token' -r ~/.scwrc`
REGION="fr-par"
ORGANIZATION_ID=`jq '.organization' -r ~/.scwrc`

LB_NAME=$1
LB_IP=$2

IP_ID=$(http GET "https://api.scaleway.com/lb/v1/regions/$REGION/ips" X-Auth-Token:$TOKEN | jq -r ".ips[] | select(.ip_address == \"$LB_IP\") | .id")
echo "IP_ID: $IP_ID"

http POST "https://api.scaleway.com/lb/v1/regions/$REGION/lbs" X-Auth-Token:$TOKEN name=$LB_NAME organization_id=$ORGANIZATION_ID ip_id=$IP_ID --ignore-stdin | jq -r '.id'
