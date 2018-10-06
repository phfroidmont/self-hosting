#!/bin/bash

set -e

SOURCE_HOST=195.154.134.7

#Sync Media
rsync -aAvh --progress root@${SOURCE_HOST}:/media/ /data --delete

#Sync Backups
rsync -aAvh --progress root@${SOURCE_HOST}:/backups/ /backups --delete

#Sync Deluge
mkdir -p {{docker_compose_files_folder}}/deluge
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder}}/torrent/config/ {{docker_compose_files_folder}}/deluge/config --delete
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/deluge/ /var/lib/deluge --delete

#Sync emby
mkdir -p {{docker_compose_files_folder}}/emby
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder}}/emby/config/ {{docker_compose_files_folder}}/emby/config --delete

#Sync Mailu
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/mailu/ /var/lib/mailu --delete

#Sync matrix
mkdir -p {{docker_compose_files_folder}}/matrix
mkdir -p /var/lib/matrix
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder}}/matrix/synapse/ {{docker_compose_files_folder}}/matrix/synapse --delete
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/matrix/media_store/ /var/lib/matrix/media_store --delete

#Sync nextcloud
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/nextcloud/ /var/lib/nextcloud --exclude "db" --delete

#Sync Wiki
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/wiki/ /var/lib/wiki --delete

#Sync certificates
mkdir -p {{docker_compose_files_folder}}/traefik/certs/
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder}}/traefik/certs/ {{docker_compose_files_folder}}/traefik/certs --delete

