base-docker
===========
Installs and configures docker

Role Variables
--------------
`docker_compose_files_folder` The path where all the compose projects folders will be stored
`docker_compose_persistence_folder` The path where all persistent data will be stored, defaults to `/var/lib`

Dependencies
------------
- base
