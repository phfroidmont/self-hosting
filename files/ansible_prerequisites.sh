#!/bin/bash
set -e
pacman -Syu --noconfirm
pacman -S python --noconfirm
touch /root/.ansible_prerequisites_installed
