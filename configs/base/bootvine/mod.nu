use module.nu *
use ../boot/boot.nu [cmdline-set cmdline-unset hooks-read hooks-write hooks-insert]

const INSTALL_HOOK = "/usr/lib/initcpio/install/sd-bootvine"
const UNITS = [bootvine.service bootvine-shutdown.service]
# The console's 16 colours from the first frame on, so bootvine, the passphrase popup and ly share one palette; ly's
# config.ini picks its exact hex from these, since the console maps 24-bit colours onto the nearest slot.
export const CONSOLE_PALETTE = [
    "0b0e14" f07178 aad94c e6b450 "39bae6" d2a6ff "1c6e8c" bfbdb6
    "565b66" f07178 aad94c e6b450 "39bae6" d2a6ff "39bae6" bfbdb6
]

# bootvine draws the systemd job tree on tty12 from the initrd on and answers ask-password requests (the LUKS
# passphrase, the TPM2 pin) in a popup there; systemd's console agent stays as the fallback on tty1.
export const meta = {packages: {native: [bootvine]}, inputs: [$INSTALL_HOOK]}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    let units = if ($INSTALL_HOOK | path exists) { $UNITS | each { unit-enable $in } } else { [] }
    [(step hooks) ...$units]
}

# A hook without its install script fails every mkinitcpio: plymouth's left with its package (migration 0016 drops it
# first), and sd-bootvine waits for its own (hooks-sweep drops it once the package leaves). It goes right after
# systemd; a busybox initrd has no systemd to hook into, so bootvine then starts in stage 2 only.
export def hooks-placed [hooks: list<string>, installed: bool]: nothing -> list<string> {
    let kept = $hooks | where $it != plymouth and ($installed or $it != sd-bootvine)
    if not $installed or "sd-bootvine" in $kept or "systemd" not-in $kept { return $kept }
    hooks-insert $kept sd-bootvine systemd --after
}

# The red, green and blue lines: each comma-joined channel of every palette slot, in slot order.
export def palette-channels [palette: list<string>]: nothing -> list<string> {
    [0 2 4] | each {|at| $palette | each { $"0x($in | str substring $at..($at + 1))" | into int } | str join "," }
}

# vt.default_red, _grn and _blu: the palette as the kernel's default, so a VT reset keeps it too.
export def palette-cmdline [palette: list<string>]: nothing -> list<string> {
    [red grn blu] | zip (palette-channels $palette) | each { $"vt.default_($in.0)=($in.1)" }
}

export def hooks []: nothing -> nothing {
    let hooks = hooks-read
    if "systemd" not-in $hooks {
        print "note: bootvine: HOOKS has no systemd hook, so bootvine starts after the initrd"
    }
    hooks-write (hooks-placed $hooks ($INSTALL_HOOK | path exists))
    # splash was plymouth's; auto still prints systemd's status lines for a slow or failed unit when bootvine is gone;
    # console=tty1 keeps /dev/console off the VT bootvine holds in front, so the console agent and an emergency
    # shell open on tty1
    cmdline-unset splash
    cmdline-set quiet loglevel=3 rd.udev.log_level=3 systemd.show_status=auto console=tty1 ...(palette-cmdline $CONSOLE_PALETTE)
}
