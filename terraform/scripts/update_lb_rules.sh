#!/bin/bash

set -e
set -x

export TOKEN=`jq '.token' -r ~/.scwrc`
REGION="fr-par"
ORGANIZATION_ID=`jq '.organization' -r ~/.scwrc`

LB_IP=$1
LB_TARGET_IPS=$2

function create_rules() {
    LB_ID=$1
    declare -A RULES
    RULES[http]=80
    RULES[https]=443

    for PROTOCOL in "${!RULES[@]}"; do
        PORT=${RULES[$PROTOCOL]}
        BACKEND_ID=$(http POST "https://api.scaleway.com/lb/v1/regions/$REGION/lbs/$LB_ID/backends" X-Auth-Token:$TOKEN name=lbb-$PROTOCOL forward_protocol=tcp forward_port=$PORT forward_port_algorithm=roundrobin sticky_sessions=none health_check:="{\"http_config\":{\"uri\":\"/\",\"method\":\"GET\",\"code\":404},\"check_delay\":1001,\"check_max_retries\":3,\"check_timeout\":3000,\"port\":$PORT}" server_ip:=$LB_TARGET_IPS --ignore-stdin | jq -r '.id')
        http POST "https://api.scaleway.com/lb/v1/regions/$REGION/lbs/$LB_ID/frontends" X-Auth-Token:$TOKEN backend_id=$BACKEND_ID inbound_port=$PORT name=lbf-$PROTOCOL --ignore-stdin
    done
}

function update_rules() {
    LB_ID=$1
    BACKENDS_IDS$2

    for BACKEND_ID in $BACKENDS_IDS
    do
        http PUT "https://api.scaleway.com/lb/v1/regions/$REGION/backends/$BACKEND_ID/servers" X-Auth-Token:$TOKEN server_ip:="$LB_TARGET_IPS" --ignore-stdin
    done
}

IP_ID=$(http GET "https://api.scaleway.com/lb/v1/regions/$REGION/ips" X-Auth-Token:$TOKEN | jq -r ".ips[] | select(.ip_address == \"$LB_IP\") | .id")
echo "IP_ID: $IP_ID"

LB_ID=$(http GET "https://api.scaleway.com/lb/v1/regions/$REGION/lbs" X-Auth-Token:$TOKEN | jq -r ".lbs[] | select(.ip[0].id == \"$IP_ID\") | .id")

BACKENDS_IDS=$(http GET "https://api.scaleway.com/lb/v1/regions/$REGION/lbs/$LB_ID/backends" X-Auth-Token:$TOKEN | jq -r ".backends[] | .id")

if [ -n "$BACKENDS_IDS" ]
then
    update_rules $LB_ID $BACKENDS_IDS
else
    create_rules $LB_ID
fi
