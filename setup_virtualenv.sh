#!/bin/bash

virtualenv .virtualenv
. .virtualenv/bin/activate
pip install ansible hcloud netaddr
