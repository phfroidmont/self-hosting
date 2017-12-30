#!/bin/bash

set -e
docker-compose exec gitlab chown -R $1:$1 /var/opt/gitlab/backups
docker-compose exec gitlab gitlab-rake gitlab:backup:restore force=yes