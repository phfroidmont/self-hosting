#!/bin/bash

for dir in {{docker_compose_files_folder}}/*
do
	if [ -d ${dir} ]
	then
		echo "docker-compose $1 ${dir}"
		cd "${dir}"
	       	docker-compose $1
		echo --------------------------------------------------------------
	fi
done;

