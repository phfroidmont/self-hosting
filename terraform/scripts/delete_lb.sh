#!/bin/bash

set -e
set -x

export TOKEN=`jq '.token' -r ~/.scwrc`
REGION="fr-par"
ORGANIZATION_ID=`jq '.organization' -r ~/.scwrc`

LB_IP=$1

IP_ID=$(http GET "https://api.scaleway.com/lb/v1/regions/$REGION/ips" X-Auth-Token:$TOKEN | jq -r ".ips[] | select(.ip_address == \"$LB_IP\") | .id")
echo "IP_ID: $IP_ID"

LB_ID=$(http GET "https://api.scaleway.com/lb/v1/regions/$REGION/lbs" X-Auth-Token:$TOKEN | jq -r ".lbs[] | select(.ip[0].id == \"$IP_ID\") | .id")

http DELETE "https://api.scaleway.com/lb/v1/regions/$REGION/lbs/$LB_ID" X-Auth-Token:$TOKEN
