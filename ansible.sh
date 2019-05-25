#! /usr/bin/env nix-shell
#! nix-shell -i bash -p ansible jq

set -e

SCW_TOKEN=`jq '.token' -r ~/.scwrc`

ansible-playbook "$@"
