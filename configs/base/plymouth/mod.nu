use module.nu *
use ../boot/boot.nu [cmdline-set cmdline-unset hooks-read hooks-write hooks-insert]

export const meta = {packages: {native: [plymouth]}}

const THEME = "cyberpunk"

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (files-into $"/usr/share/plymouth/themes/($THEME)" ...(glob $"theme/($THEME)/*.{plymouth,script,png}"))
        (step splash)
    ]
}

export def splash []: nothing -> nothing {
    # plymouth 24 dropped sd-plymouth, the plain hook covers a systemd initramfs too
    let hooks = hooks-read | each { if $in == "sd-plymouth" { "plymouth" } else { $in } }
    let placed = if "plymouth" in $hooks { $hooks } else {
        let anchor = [kms systemd udev base] | where $it in $hooks | get --optional 0
        if $anchor == null { error make {msg: "plymouth: HOOKS has no kms/systemd/udev/base to insert after"} }
        hooks-insert $hooks plymouth (($hooks | enumerate | where item == $anchor | get 0.index) + 1)
    }
    hooks-write $placed
    ^plymouth-set-default-theme $THEME
    # ly shares tty1 with the console; loglevel=3 keeps kernel and unit status lines off its password field
    cmdline-set quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false
    # the cursor is hidden on ly's tty only, a global one would hide it on recovery ttys too
    cmdline-unset vt.global_cursor_default
}
