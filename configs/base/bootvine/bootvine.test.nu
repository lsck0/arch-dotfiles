#!/usr/bin/env -S nu --no-config-file
# hooks-placed on the HOOKS lines a machine can have: sd-bootvine goes right after systemd once its install script is
# there, and a line without systemd stays as it is. palette-cmdline splits each colour into the kernel's three decimal
# lists, in slot order.

use mod.nu [hooks-placed palette-cmdline]

const PALETTE_WANT = ["vt.default_red=11,255" "vt.default_grn=14,128" "vt.default_blu=20,0"]

const CASES = [
    [name hooks installed want];
    [
        "sd-bootvine after systemd"
        [base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck]
        true
        [base systemd sd-bootvine autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck]
    ]
    ["already placed stays put" [base systemd sd-bootvine block filesystems] true [base systemd sd-bootvine block filesystems]]
    ["package not there yet" [base systemd block filesystems] false [base systemd block filesystems]]
    ["busybox initrd" [base udev block encrypt filesystems] true [base udev block encrypt filesystems]]
]

def main [] {
    let failed = $CASES | where {|c| (hooks-placed $c.hooks $c.installed) != $c.want }
    for c in $failed {
        print --stderr $"bootvine.test: ($c.name): got (hooks-placed $c.hooks $c.installed | str join ' ')"
    }
    if ($failed | is-not-empty) { error make {msg: $"bootvine.test: ($failed | length) of ($CASES | length) cases failed"} }
    let palette = palette-cmdline ["0b0e14" ff8000]
    if $palette != $PALETTE_WANT { error make {msg: $"bootvine.test: palette-cmdline: got ($palette | str join ' ')"} }
}
