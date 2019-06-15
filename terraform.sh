#! /usr/bin/env nix-shell
#! nix-shell -i bash -p terraform jq

set -e

export AWS_ACCESS_KEY_ID=`cat ~/.ssh/scw_key_id`
export AWS_SECRET_ACCESS_KEY=`jq '.token' -r ~/.scwrc`

terraform "$@" terraform

