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

# ! TODO !

# Afterwards call "fin" to update the repo

fin
