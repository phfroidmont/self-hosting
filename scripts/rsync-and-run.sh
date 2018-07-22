#!/bin/bash
DIRECTORY=`dirname $0`
cd DIRECTORY/..
rsync -avzhe ssh --delete --exclude=.* ./ root@163.172.145.22:/root/ansible && ssh -t root@163.172.145.22 "cd ansible && $1"
