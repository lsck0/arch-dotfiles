#!/usr/bin/env -S nu --no-config-file
# hooks-placed on the HOOKS lines a machine can have: plymouth always goes, sd-bootvine sits right after systemd only
# while its install script is there, since a hook without one fails every mkinitcpio.

use mod.nu [hooks-placed]

const CASES = [
    [name hooks installed want];
    [
        "plymouth swapped for sd-bootvine"
        [base systemd autodetect microcode modconf kms plymouth keyboard sd-vconsole block sd-encrypt filesystems fsck]
        true
        [base systemd sd-bootvine autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck]
    ]
    ["already placed stays put" [base systemd sd-bootvine block filesystems] true [base systemd sd-bootvine block filesystems]]
    ["package not there yet" [base systemd plymouth block filesystems] false [base systemd block filesystems]]
    ["package removed" [base systemd sd-bootvine block filesystems] false [base systemd block filesystems]]
    ["busybox initrd" [base udev plymouth block encrypt filesystems] true [base udev block encrypt filesystems]]
]

def main [] {
    let failed = $CASES | where {|c| (hooks-placed $c.hooks $c.installed) != $c.want }
    for c in $failed {
        print --stderr $"bootvine.test: ($c.name): got (hooks-placed $c.hooks $c.installed | str join ' ')"
    }
    if ($failed | is-not-empty) { error make {msg: $"bootvine.test: ($failed | length) of ($CASES | length) cases failed"} }
}
