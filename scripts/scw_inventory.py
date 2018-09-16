#!/usr/bin/env python3
# -*- coding: utf-8 -*-
'''
Generate an inventory of servers from scaleway which is
suitable for use as an ansible dynamic inventory
Right now, only the group 'cci-customer' is exported
'''

import argparse
import os
import json
import configparser

from scaleway.apis import ComputeAPI

class SCWInventory(object):
    '''
    The inventory class which calls out to scaleway and digests
    the returned data, making it usable by ansible as an inventory
    '''
    def __init__(self):
        self.inventory = None
        self.auth_token = None
        self.environment = None
        self.response = {
            '_meta': {
                'hostvars': {
                }
            }
        }

    def parse_config(self, creds_file='scw.ini'):
        '''
        Parse the ini file to get the auth token
        '''
        config = configparser.ConfigParser()
        config.read(creds_file)
        with open(os.path.expanduser(config['credentials']['token_file']), 'r') as content_file:
            self.auth_token = content_file.read().replace('\n', '')
        self.environment = config['config']['environment']

    def get_servers(self):
        '''
        query scaleway api and pull down a list of servers
        '''
        self.parse_config()
        api_par1 = ComputeAPI(auth_token=self.auth_token, region='par1')
        api_ams1 = ComputeAPI(auth_token=self.auth_token, region='ams1')
        result_par1 = api_par1.query().servers.get()
        result_ams1 = api_ams1.query().servers.get()
        self.inventory = [
            [i['name'], i['public_ip'], i['tags'], i['private_ip']] for i in result_par1['servers'] + result_ams1['servers']
        ]
        for host, ip_info, tags, private_ip in self.inventory:
            host_vars = {
                'private_ip': private_ip,
                'ansible_python_interpreter': '/usr/bin/python3'
            }
            if ip_info:
                host_vars['ansible_host'] = ip_info['address']
                host_vars['public_ip'] = ip_info['address']
            else:
                host_vars['ansible_host'] = private_ip

            self.response['_meta']['hostvars'][host] = host_vars
            if tags:
                for tag in tags:
                    self._add_to_response(
                        tag,
                        host
                    )

        for host, variables in self.response['_meta']['hostvars'].items():
            if host != 'proxy1':
                variables['ansible_ssh_common_args'] = '-o ProxyCommand="ssh -W %h:%p -q root@' + self.response['_meta']['hostvars']['proxy1']['public_ip'] + '"'

    def _add_to_response(self, group, hostname):
        '''
        add a host to a group within the response
        '''
        if group not in self.response:
            self.response[group] = list()
        if group in self.response:
            self.response[group].append(hostname)

    def print_inventory(self):
        '''
        simply display the collected inventory
        '''
        print(json.dumps(self.response))

def main():
    '''
    run the program starting here
    '''
    inventory = SCWInventory()
    inventory.get_servers()
    inventory.print_inventory()

if __name__ == '__main__':
    main()
