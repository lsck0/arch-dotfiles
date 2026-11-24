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
# off for every paired device: chats and contacts stay on the phone, and nothing on it drives this machine
const PLUGINS_OFF = [
    kdeconnect_notifications kdeconnect_sendnotifications kdeconnect_sms kdeconnect_contacts kdeconnect_mousepad
    kdeconnect_remotekeyboard kdeconnect_runcommand kdeconnect_lockdevice kdeconnect_shareinputdevices
    kdeconnect_shareinputdevicesremote kdeconnect_digitizer kdeconnect_presenter
]
const DEVICES_PATH = "/modules/kdeconnect/devices"

# a running daemon keeps a device's plugins loaded until told to reload them; a stopped one reads the config on start
def device-plugins-reload [id: string]: nothing -> list<string> {
    let call = $"busctl --user --auto-start=no call org.kde.kdeconnect ($DEVICES_PATH)/($id) org.kde.kdeconnect.device reloadPlugins"
    [sh -c $"! busctl --user --auto-start=no status org.kde.kdeconnect >/dev/null 2>&1 || ($call)"]
}

export def link [cfg: record] {
    let config = xdg config kdeconnect
    let trusted = $config | path join trusted_devices
    # one section per paired device
    let ids = if ($trusted | path exists) {
        ini-rows (open --raw $trusted) | get section | uniq | where $it != ""
    } else { [] }
    let clipboard = {General: {autoShare: ($cfg.clipboard_auto | into string), sendPassword: "false"}}
    let plugins = {Plugins: ($PLUGINS_OFF | each {|p| {$"($p)Enabled": "false"} } | into record)}
    [
        (link-commands scripts/phone.nu)
        ($ids | each {|id| ini-merge ($config | path join $id $CLIPBOARD_PLUGIN config) $clipboard })
        ($ids | each {|id| ini-merge ($config | path join $id config) $plugins --then (device-plugins-reload $id) })
    ]
}
