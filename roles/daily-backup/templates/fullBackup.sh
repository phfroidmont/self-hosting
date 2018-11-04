#!/bin/sh
set -e

touch /backups/backup-ongoing

REPOSITORY=ssh://backup@phf.ddns.net:2222/./backup

export BORG_PASSPHRASE='{{backup_borg_passphrase}}'

echo 'Dumping NextCloud database'
docker exec nextcloud_db_1 sh -c "mysqldump -u nextcloud -p{{nextcloud_mysql_password}} nextcloud > /backups/database.dmp"

echo 'Dumping S.T.B. wordpress database'
docker exec stb_db_1 sh -c "mysqldump -u stb -p{{stb_mysql_password}} stb > /backups/database.dmp"

echo 'Dumping matrix database'
docker exec matrix_db_1 sh -c "pg_dump -U synapse synapse > /backups/database.dmp"

echo 'Copying murmur database'
docker stop murmur_murmur_1
cp /var/lib/murmur/murmur.sqlite /backups/murmur/murmur.sqlite
docker start murmur_murmur_1

echo 'Creating GitLab backup'
docker exec gitlab_gitlab_1 gitlab-rake gitlab:backup:create

echo 'Starting Borg backup'
borg create -v --stats --compression lz4           \
    ${REPOSITORY}::'{hostname}-{now:%Y-%m-%d}'     \
    /root                                          \
    /home                                          \
    /data                                          \
    /etc                                           \
    /var/lib/transmission                          \
    /var/lib/mailu                                 \
    /var/lib/matrix/media_store                    \
    /var/lib/nextcloud                             \
    /var/lib/wiki                                  \
    /var/lib/stb                                   \
    /var/lib/nzbget                                \
    /opt/factorio                                  \
    /backups                                       \
    --exclude '/var/lib/nextcloud/db'

# Route the normal process logging to journalctl
2>&1

# If there is an error backing up, reset password envvar and exit
if [ "$?" = "1" ] ; then
    export BORG_PASSPHRASE=""
    exit 1
fi

# Use the `prune` subcommand to maintain 14 daily, 8 weekly and 12 monthly
# archives of THIS machine. The '{hostname}-' prefix is very important to
# limit prune's operation to this machine's archives and not apply to
# other machine's archives also.
borg prune -v --list ${REPOSITORY} --prefix '{hostname}-' \
    --keep-daily=14 --keep-weekly=8 --keep-monthly=12

# Unset the password
export BORG_PASSPHRASE=""

rm -f /backups/backup-ongoing
touch /backups/backup-ok

exit 0
