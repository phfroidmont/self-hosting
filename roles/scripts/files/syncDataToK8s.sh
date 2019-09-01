#!/bin/bash

set -e

DESTINATION_HOST=116.203.8.164

rsync -aAvh -e 'ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 30522' --progress /var/lib/wiki/ root@${DESTINATION_HOST}:/data/wiki --delete
