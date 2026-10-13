#!/usr/bin/env bash

# a guest's own 192.168.122.0/24 would collide with a nested default network
if ! command -v virsh >/dev/null 2>&1 || [[ "$FORM_FACTOR" =~ ^(vm|wsl)$ ]]; then
    exit 0
fi

# pinned, not left to the distro default: the idle-out can't regress to never (the bridge stays regardless)
dropin_install libvirtd.service libvirtd-timeout.conf || true
# autostart only fires when libvirtd runs: start it at boot so virbr0 exists; it idles out after the pinned 120 s, the
# bridge stays. --now before any virsh: root's qemu:///system never autostarts a daemon, so a fresh install would abort here
systemctl enable --now libvirtd.service

# boxes bridges new vms to virbr0 when it exists, else uses slirp, where portmaster filters guest flows as qemu's and refuses the guest's dns-over-tls
virsh_system() { virsh -q -c qemu:///system "$@"; }
virsh_system net-autostart default >/dev/null
virsh_system net-info default | grep -q '^Active:.*yes' || virsh_system net-start default

# no libvirt group: its polkit rule is a silent root for every process of a member; qemu:///system asks an admin
# (49-libvirt.rules), kvm is enough for qemu:///session + /dev/kvm
install -Dm644 49-libvirt.rules /etc/polkit-1/rules.d/49-libvirt.rules
group_add_admins kvm

# nested virtualization, so a guest can itself run VMs
if grep -q AuthenticAMD /proc/cpuinfo; then
    echo "options kvm_amd nested=1" >/etc/modprobe.d/kvm-nested.conf
elif grep -q GenuineIntel /proc/cpuinfo; then
    echo "options kvm_intel nested=1" >/etc/modprobe.d/kvm-nested.conf
fi
