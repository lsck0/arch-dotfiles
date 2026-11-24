#!/usr/bin/env -S nu --no-config-file
# drives-from keeps only removable or hot-pluggable drives that hold media, names them by vendor and model, and lists
# every filesystem under them: a mounted one with its usage, an open LUKS container by what is inside it, a closed one
# as locked. error-from reduces udisksctl's wrapped refusal to the reason.
use drives.nu [drives-from error-from]

const GIB = 1073741824
const NODE = {
    rm: false, hotplug: false, label: null, fstype: null, mountpoints: [null], fsused: null, fssize: null, model: null,
    vendor: null, tran: null, ro: false
}

def fail [msg: string] { error make {msg: $"drives.test: ($msg)"} }

def node [name: string, type: string, fields: record = {}]: nothing -> record {
    $NODE | merge {name: $name, path: $"/dev/($name)", type: $type, size: $GIB} | merge $fields
}

def volume [name: string, fstype: string, fields: record = {}]: nothing -> record {
    {
        path: $"/dev/($name)", name: $name, label: "", fstype: $fstype, sizeBytes: $GIB, mountpoint: "", usedBytes: null,
        fsSizeBytes: null, locked: false, readOnly: false
    } | merge $fields
}

def drive-cases [] {
    let internal = node nvme0n1 disk {tran: nvme, children: [(node nvme0n1p1 part {fstype: vfat, mountpoints: ["/boot"]})]}
    let stick = node sda disk {
        rm: true, vendor: "SanDisk ", model: "Cruzer", tran: usb
        children: [
            (node sda1 part {fstype: vfat, label: STICK, mountpoints: ["/run/media/u/STICK"], fsused: 100, fssize: 900})
            (node sda2 part {fstype: crypto_LUKS})
        ]
    }
    let ssd = node sdb disk {
        hotplug: true, tran: usb
        children: [(node sdb1 part {fstype: crypto_LUKS, children: [(node luks-x crypt {fstype: ext4, path: "/dev/mapper/luks-x"})]})]
    }
    let bare = node sdc disk {rm: true, fstype: exfat, mountpoints: [null]}
    let empty_reader = node sdd disk {rm: true, size: 0}
    let optical = node sr0 rom {rm: true, fstype: iso9660, ro: true}
    let cases = [
        [name devices want];
        [none [$internal] []]
        [stick [$internal $stick] [{
            path: /dev/sda, name: "SanDisk Cruzer", sizeBytes: $GIB, transport: usb, canPowerOff: true
            volumes: [
                (volume sda1 vfat {label: STICK, mountpoint: "/run/media/u/STICK", usedBytes: 100, fsSizeBytes: 900})
                (volume sda2 crypto_LUKS {locked: true})
            ]
        }]]
        [open-luks [$ssd] [{
            path: /dev/sdb, name: sdb, sizeBytes: $GIB, transport: usb, canPowerOff: true
            volumes: [(volume luks-x ext4 {path: "/dev/mapper/luks-x"})]
        }]]
        [unpartitioned [$bare] [{path: /dev/sdc, name: sdc, sizeBytes: $GIB, transport: "", canPowerOff: true, volumes: [(volume sdc exfat)]}]]
        [no-media [$empty_reader] []]
        [optical [$optical] [{
            path: /dev/sr0, name: sr0, sizeBytes: $GIB, transport: "", canPowerOff: false
            volumes: [(volume sr0 iso9660 {readOnly: true})]
        }]]
    ]
    for c in $cases {
        let got = drives-from {blockdevices: $c.devices}
        if $got != $c.want { fail $"($c.name): ($got | to nuon)" }
    }
}

def error-cases [] {
    let cases = [
        [stderr want];
        ["Error unmounting /dev/sdb1: GDBus.Error:org.freedesktop.UDisks2.Error.DeviceBusy: Error unmounting /dev/sdb1: target is busy\n" "target is busy"]
        ["Error mounting /dev/sda1: GDBus.Error:org.freedesktop.UDisks2.Error.NotAuthorizedDismissed: Not authorized to perform operation" "Not authorized to perform operation"]
        ["Object /dev/sdz not found" "Object /dev/sdz not found"]
    ]
    for c in $cases {
        let got = error-from $c.stderr
        if $got != $c.want { fail $"error-from ($c.stderr | str trim): ($got)" }
    }
}

def main [] {
    drive-cases
    error-cases
}
