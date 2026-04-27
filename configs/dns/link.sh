#!/usr/bin/env bash
# Split DNS setup for homelab.
# Routes *.lsck0.dev queries to the homelab router (CoreDNS).

set -ex

ROUTER_IP="192.168.178.29"
DOMAIN="lsck0.dev"

sudo mkdir -p /etc/NetworkManager/conf.d /etc/NetworkManager/dnsmasq.d

sudo cat > /etc/NetworkManager/conf.d/dns.conf << EOF
[main]
dns=dnsmasq
EOF

sudo cat > /etc/NetworkManager/dnsmasq.d/${DOMAIN//./-}.conf << EOF
server=/${DOMAIN}/${ROUTER_IP}
EOF
