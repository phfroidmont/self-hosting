Self-hosting
============
This project maintains the entire configuration of our self-hosted services.
All configuration should be done exclusively in this repo so that everything is versioned and we have a reliable and esay way to restore the production to any given state.
The deployement of the configuration is done with Ansible. Everything respects the basic Ansible principle that your configuration should be idempotent. It means that that the configuration is completely independent of the current state of the server so whatever the state of the server is, the resulting state should always be the same.
Because of this you shouldn't hesitate to run Ansible often to make sure that the configuration works and the server is in the expected state.
If you run `ansible-playbook` two times in a row, the second execution should result in no changes to be made.

Deploying the configuration
---------------------------
The following command deploys the complete configuration.
```bash
ansible-playbook -i production playbook.yml --ask-vault-pass
```
For this to work, you must of course have ansible installed and have ssh access to the server(s).
You will be prompted for the vault password, ask for it if you don't have it.

Deploying specific parts of the configuration
---------------------------------------------
You probably don't want to deploy the entire configuration every time you make a small change.
You can deploy specific roles by providing a list of tags. Checkout `playbook.yml` to see which tag matches a specific role.
Here is an example of deploying only the wiki and the reverse proxy:
```bash
ansible-playbook -i production playbook.yml --ask-vault-pass --tags wiki,traefik
```

