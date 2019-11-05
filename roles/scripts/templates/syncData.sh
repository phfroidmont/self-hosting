#!/bin/bash

set -e

SOURCE_HOST=5.9.66.49

#Sync Media
rsync -aAvh --progress root@${SOURCE_HOST}:/data/ /data --delete

#Sync Backups
rsync -aAvh --progress root@${SOURCE_HOST}:/backups/ /backups --delete

#Sync Torrents
mkdir -p {{docker_compose_files_folder}}/torrent
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder_previous_server}}/torrent/config/ {{docker_compose_files_folder}}/torrent/config --delete
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/transmission/ /var/lib/transmission --delete

#Sync emby
mkdir -p {{docker_compose_files_folder}}/emby
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder_previous_server}}/emby/config/ {{docker_compose_files_folder}}/emby/config --exclude "transcoding-temp"  --delete

#Sync matrix
mkdir -p {{docker_compose_files_folder}}/matrix
mkdir -p /var/lib/matrix
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder_previous_server}}/matrix/synapse/ {{docker_compose_files_folder}}/matrix/synapse --delete
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/matrix/media_store/ /var/lib/matrix/media_store --delete
rsync -aAvh --progress root@${SOURCE_HOST}:/var/log/synapse/ /var/log/synapse --delete

#Sync nextcloud
mkdir -p {{docker_compose_files_folder}}/nextcloud/config
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder_previous_server}}/nextcloud/config/ {{docker_compose_files_folder}}/nextcloud/config --delete
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/nextcloud/ /var/lib/nextcloud --delete

#Sync Wiki
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/wiki/ /var/lib/wiki --delete

#Sync certificates
mkdir -p {{docker_compose_files_folder}}/traefik/certs/
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder_previous_server}}/traefik/certs/ {{docker_compose_files_folder}}/traefik/certs --delete

#Sync factorio
mkdir -p /opt/factorio
rsync -aAvh --progress root@${SOURCE_HOST}:/opt/factorio/ /opt/factorio --delete

#Sync STB wordpress
mkdir -p /var/lib/stb
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/stb/ /var/lib/stb --delete
rsync -aAvh --progress root@${SOURCE_HOST}:{{docker_compose_files_folder_previous_server}}/stb/ {{docker_compose_files_folder}}/stb --delete

#Sync Mailu
rsync -aAvh --progress root@${SOURCE_HOST}:/var/lib/mailu/ /var/lib/mailu --delete
