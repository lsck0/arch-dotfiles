use module.nu *
use ../boot/boot.nu [cmdline-set hooks-read hooks-write hooks-insert]

export const meta = {packages: {native: [plymouth]}, inputs: [/usr/lib/initcpio/install/plymouth]}

const THEME = "cyberpunk"

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (files-into $"/usr/share/plymouth/themes/($THEME)" ...(glob $"theme/($THEME)/*.{plymouth,script,png}"))
        (step splash)
    ]
}

const INSTALL_HOOK = "/usr/lib/initcpio/install/plymouth"

export def splash []: nothing -> nothing {
    # a hook without its install script fails every mkinitcpio
    if not ($INSTALL_HOOK | path exists) { return }
    let hooks = hooks-read
    let placed = if "plymouth" in $hooks { $hooks } else {
        let anchor = [kms systemd udev base] | where $it in $hooks | get --optional 0
        if $anchor == null { error make {msg: "plymouth: HOOKS has no kms/systemd/udev/base to insert after"} }
        hooks-insert $hooks plymouth (($hooks | enumerate | where item == $anchor | get 0.index) + 1)
    }
    hooks-write $placed
    ^plymouth-set-default-theme $THEME
    cmdline-set quiet splash loglevel=3 rd.udev.log_level=3 systemd.show_status=false
}
