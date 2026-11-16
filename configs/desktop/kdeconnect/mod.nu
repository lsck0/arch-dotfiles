# The phone link: KDE Connect's daemon starts from its XDG autostart entry and on D-Bus activation; `phone` sends to it.
use module.nu *
use ini.nu [ini-rows]

export const meta = {
    packages: {pacman: [kdeconnect libnotify wl-clipboard]}
    # the per-device clipboard config follows the paired devices in kdeconnect's own state
    volatile: true
}

export const options = {
    clipboard_auto: {
        type: bool
        default: false
        doc: "Send every desktop copy to the paired phone, passwords from a password manager excluded"
        label: "Clipboard to phone on copy"
        apply: relink
        scope: user
    }
}

const CLIPBOARD_PLUGIN = "kdeconnect_clipboard"

export def link [cfg: record] {
    let config = xdg config kdeconnect
    let trusted = $config | path join trusted_devices
    # one section per paired device
    let ids = if ($trusted | path exists) {
        ini-rows (open --raw $trusted) | get section | uniq | where $it != ""
    } else { [] }
    let clipboard = {General: {autoShare: ($cfg.clipboard_auto | into string), sendPassword: "false"}}
    [
        (link-commands phone.nu)
        ($ids | each {|id| ini-merge ($config | path join $id $CLIPBOARD_PLUGIN config) $clipboard })
    ]
}
