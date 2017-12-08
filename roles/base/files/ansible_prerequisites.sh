#!/bin/bash
set -e
#pacman -Syu --noconfirm   #Skip this step because reboot is needed to start docker in case of kernel update
pacman -S python --noconfirm
touch /root/.ansible_prerequisites_installed
