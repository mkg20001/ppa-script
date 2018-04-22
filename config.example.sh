#!/bin/bash

OUT="/var/www/html/ubuntu"
KEY="YOURKEY"

# Create repo

_init

# Add distros and archs

for distro in xenial bionic; do
  add_dist "$distro" "EXAMPLE-PPA-$distro" "Yet another example PPA"
  add_comp "$distro" main
  add_arch "$distro" amd64
  add_arch "$distro" i386
done

# Download some packages

# Download latest anydesk

for anydesk_deb in $(curl -s https://anydesk.de/download?os=linux | grep '.deb"' | grep -o "https.*.deb"); do
  add_url_auto anydesk "$anydesk_deb"
done

# Afterwards call "fin" to update the repo

fin
