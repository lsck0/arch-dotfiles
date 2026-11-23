#!/usr/bin/env -S setpriv --pdeathsig TERM nu --no-config-file
# Removable and hot-pluggable drives for the bar's drives widget, and the udisks2 actions on them.
# `list` prints one JSON line: the drives, each with its volumes. `mount`, `unmount` and `eject` act through
# udisksctl (polkit lets the active session do it) and print udisks' reason alone on stderr when it refuses.

const LSBLK_COLUMNS = "NAME,PATH,TYPE,RM,HOTPLUG,SIZE,LABEL,FSTYPE,MOUNTPOINTS,FSUSED,FSSIZE,MODEL,VENDOR,TRAN,RO"
const DRIVE_TYPES = [disk rom]
const LOCKED_FSTYPE = "crypto_LUKS"
# udisksctl wraps a refusal in its own prefixes: "Error mounting /dev/sdb1: GDBus.Error:org.freedesktop...: <reason>"
const ERROR_PREFIXES = ['^Error [a-z ]+ \S+: ' '^GDBus\.Error:[\w.]+: ']

def lsblk-load [...devices: string]: nothing -> record {
    ^lsblk -J -b -o $LSBLK_COLUMNS ...$devices | from json
}

def node-mountpoint [node: record]: nothing -> string {
    $node.mountpoints? | default [] | compact | get 0? | default ""
}

def nodes-flatten [node: record]: nothing -> list<record> {
    [$node] | append ($node.children? | default [] | each {|child| nodes-flatten $child } | flatten)
}

# every node of a tree under a drive that carries a filesystem, outermost first; a LUKS container with its mapping
# open is replaced by what is inside it
def volumes-from [node: record]: nothing -> list<record> {
    let children = $node.children? | default []
    let inner = $children | each {|child| volumes-from $child } | flatten
    if $node.fstype == null or ($node.fstype == $LOCKED_FSTYPE and ($children | is-not-empty)) { return $inner }
    let mountpoint = node-mountpoint $node
    [{
        path: $node.path
        name: $node.name
        label: ($node.label | default "")
        fstype: $node.fstype
        sizeBytes: $node.size
        mountpoint: $mountpoint
        usedBytes: (if $mountpoint == "" { null } else { $node.fsused })
        fsSizeBytes: (if $mountpoint == "" { null } else { $node.fssize })
        locked: ($node.fstype == $LOCKED_FSTYPE)
        readOnly: $node.ro
    }] | append $inner
}

# the top-level drives of an lsblk tree that are removable or hot-pluggable and hold media
export def drives-from [tree: record]: nothing -> list<record> {
    $tree.blockdevices
    | where {|d| $d.type in $DRIVE_TYPES and ($d.rm or $d.hotplug) and $d.size > 0 }
    | each {|d|
        let model = [$d.vendor $d.model] | compact | each { str trim } | where $it != "" | str join " "
        {
            path: $d.path
            name: (if $model == "" { $d.name } else { $model })
            sizeBytes: $d.size
            transport: ($d.tran | default "")
            canPowerOff: ($d.type == disk)
            volumes: (volumes-from $d)
        }
    }
}

export def error-from [stderr: string]: nothing -> string {
    mut text = $stderr | str trim
    loop {
        let stripped = $ERROR_PREFIXES | reduce --fold $text {|prefix, acc| $acc | str replace -r $prefix "" }
        if $stripped == $text { break }
        $text = $stripped
    }
    $text
}

def udisks-run [verb: string, device: string] {
    let run = ^udisksctl $verb -b $device | complete
    if $run.exit_code != 0 {
        print -e (error-from $run.stderr)
        exit 1
    }
}

def main [] {}

def "main list" [] {
    drives-from (lsblk-load) | to json -r | print
}

def "main mount" [device: string] { udisks-run mount $device }

def "main unmount" [device: string] { udisks-run unmount $device }

# unmounts every mounted volume of the drive, innermost first, locks the open LUKS containers, then powers it off
def "main eject" [drive: string] {
    let tree = lsblk-load $drive
    let mounted = drives-from $tree | get 0?.volumes | default [] | where mountpoint != "" | reverse
    for volume in $mounted { udisks-run unmount $volume.path }
    let open_containers = $tree.blockdevices | each {|d| nodes-flatten $d } | flatten
        | where {|n| $n.fstype == $LOCKED_FSTYPE and ($n.children? | default [] | is-not-empty) }
        | reverse
    for container in $open_containers { udisks-run lock $container.path }
    udisks-run power-off $drive
}
