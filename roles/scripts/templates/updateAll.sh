#!/bin/bash


for dir in {{docker_compose_files_folder}}/*
do
	if [ -d ${dir} ]
	then
		echo "Updating ${dir}"
		cd "${dir}"
	    docker-compose pull
		[ ${dir} = 'nextcloud' ] && docker-compose build --pull
		docker-compose up -d
		echo --------------------------------------------------------------
	fi
done;

