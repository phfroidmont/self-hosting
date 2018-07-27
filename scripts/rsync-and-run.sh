#!/bin/bash
DIRECTORY=`dirname $0`
cd $DIRECTORY/..
rsync -avzhe ssh --delete --exclude=.* ./ deploy@ansible.banditlair.com:/home/deploy/ansible && ssh -t deploy@ansible.banditlair.com "cd ansible && $1"
