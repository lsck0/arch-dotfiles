#!/usr/bin/env bash

# a guest's own 192.168.122.0/24 would collide with a nested default network
if ! command -v virsh >/dev/null 2>&1 || [[ "$FORM_FACTOR" =~ ^(vm|wsl)$ ]]; then
    exit 0
fi

# boxes bridges new vms to virbr0 when it exists, else uses slirp, where portmaster filters guest flows as qemu's and refuses the guest's dns-over-tls
virsh_system() { virsh -q -c qemu:///system "$@"; }
virsh_system net-autostart default >/dev/null
virsh_system net-info default | grep -q '^Active:.*yes' || virsh_system net-start default
# autostart only fires when libvirtd runs: start it at boot so virbr0 exists; it idles out after 120 s, the bridge stays
systemctl enable libvirtd.service
