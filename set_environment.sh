#!/bin/bash

set -e

if [ -z "$1" ]
then
    echo 'You must specify an environment'
    exit 1
fi

echo "$1" > .environment
./setup_virtualenv.sh
