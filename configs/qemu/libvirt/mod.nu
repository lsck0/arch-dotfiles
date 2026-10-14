use module.nu *

export const meta = {packages: {pacman: [dnsmasq gnome-boxes libvirt qemu-full virt-install]}}

const NESTED = {AuthenticAMD: kvm_amd, GenuineIntel: kvm_intel}

# a guest's own 192.168.122.0/24 would collide with a nested default network
export def system [cfg: record] {
    if (which virsh | is-empty) or $env.FORM_FACTOR? in [vm wsl] { return [] }
    let vendor = open /proc/cpuinfo | lines | parse --regex '^vendor_id\s*:\s*(?<v>\S+)' | get --optional 0.v
    let module = $NESTED | get --optional ($vendor | default "")
    [
        # autostart only fires while libvirtd runs, and root's qemu:///system never autostarts a daemon
        (unit-enable libvirtd.service --now)
        (step network)
        # no libvirt group: its polkit rule is a silent root for every member's process
        (file-copy 49-libvirt.rules /etc/polkit-1/rules.d/49-libvirt.rules)
        (group-admins kvm)
        (if $module == null { [] } else { file-text /etc/modprobe.d/kvm-nested.conf $"options ($module) nested=1\n" })
    ]
}

# slirp would leave guest flows to portmaster as qemu's, which refuses the guest's dns-over-tls
export def network []: nothing -> nothing {
    ^virsh -q -c qemu:///system net-autostart default | ignore
    if not (^virsh -q -c qemu:///system net-info default | lines | any { $in =~ '^Active:.*yes' }) {
        ^virsh -q -c qemu:///system net-start default
    }
}
