#!/bin/bash
#
# Install certificates in proxmox ve via command line
#
# args $1 certificate name
pvenode cert set "/etc/ssl/certs/${1}_fullchain.pem" "/etc/ssl/private/${1}_key.pem" --force 1 \
    && systemctl restart pveproxy