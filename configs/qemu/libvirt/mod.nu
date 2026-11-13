use module.nu *

export const meta = {packages: {pacman: [archiso dnsmasq gnome-boxes libvirt qemu-full virt-install]}}

const NESTED = {AuthenticAMD: kvm_amd, GenuineIntel: kvm_intel}
const DEFAULT_SUBNET = "192.168.122.0/24"
const DEFAULT_BRIDGE = "virbr0"
const SYSTEM_URI = "qemu:///system"

def --wrapped virsh-system [...args: string]: nothing -> any {
    ^virsh -q -c $SYSTEM_URI ...$args
}

export def system [cfg: record] {
    if (which virsh | is-empty) or $env.FORM_FACTOR? in [vm wsl] { return [] }
    let vendor = open /proc/cpuinfo | lines | parse --regex '^vendor_id\s*:\s*(?<v>\S+)' | get --optional 0.v
    let module = $NESTED | get --optional ($vendor | default "")
    [
        (unit-enable libvirtd.service --now)
        (step network)
        # no libvirt group: its polkit rule is a silent root for every member's process
        (polkit-rules 49-libvirt.rules)
        (group-admins kvm)
        (if $module != null { file-text /etc/modprobe.d/kvm-nested.conf $"options ($module) nested=1\n" })
    ]
}

# Starts libvirt's NAT network unless its subnet is taken (a nested guest); slirp would give guest dns to portmaster.
export def network []: nothing -> nothing {
    let taken = ^ip -j -4 route | from json | where dst == $DEFAULT_SUBNET and dev != $DEFAULT_BRIDGE | get --optional 0.dev
    if $taken != null {
        virsh-system net-autostart --disable default | ignore
        log-note $"libvirt: ($DEFAULT_SUBNET) is already this machine's network on ($taken), the default network stays off"
        return
    }
    virsh-system net-autostart default | ignore
    if (virsh-system net-info default | lines | any { $in =~ '^Active:.*yes' }) { return }
    virsh-system net-start default
}
