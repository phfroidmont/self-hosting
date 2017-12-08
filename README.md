How-tos
=======
Some tips on how to use this repo.

Mount last backup
-----------------
```bash
borg mount --info --foreground $REPO_FOLDER $MOUNT_POINT --last 1
```

Create a full installation of the services inside a VM
------------------------------------------------------
```bash
vagrant up #if your VM already exist it's best to do a vagrant destroy first
ansible-playbook -i staging playbook.yml -e 'backup_folder=$REPO_FOLDER'
```