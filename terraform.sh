#! /usr/bin/env nix-shell
#! nix-shell -i bash -p terraform jq

set -e

AWS_ACCESS_KEY_ID=SCW3NQVMPDWZF6HM3DR1
AWS_SECRET_ACCESS_KEY=`jq '.token' -r ~/.scwrc`

terraform "$@" terraform
