#!/bin/bash

set -e

ONGOING_FILE="/backups/backup-ongoing"

if [ -f "$ONGOING_FILE" ]
then
	if test `find "$ONGOING_FILE" -mmin +1`
	then
		LAST_MODIFICATION_HOURS=`expr "$(($(date +%s) - $(date +%s -r $ONGOING_FILE)))" / 3600`
    		echo "Backup not finished after more than $LAST_MODIFICATION_HOURS hours"
		exit 1
	fi
fi

exit 0
