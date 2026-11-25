# The phone link: KDE Connect's daemon starts from its XDG autostart entry and on D-Bus activation; `phone` sends to it.
use module.nu *
use ini.nu [ini-rows]

export const meta = {
    packages: {pacman: [kdeconnect libnotify wl-clipboard]}
    # the per-device clipboard config follows the paired devices in kdeconnect's own state
    volatile: true
}

# the plugins plugins_off governs, each declared on or off: the ini merge keeps no record to undo a dropped key, so one
# taken off the list is switched back on, and a plugin outside it keeps what the device config holds
const PLUGINS_GOVERNED = [
    kdeconnect_notifications kdeconnect_sendnotifications kdeconnect_sms kdeconnect_contacts kdeconnect_mousepad
    kdeconnect_remotekeyboard kdeconnect_runcommand kdeconnect_lockdevice kdeconnect_shareinputdevices
    kdeconnect_shareinputdevicesremote kdeconnect_digitizer kdeconnect_presenter
]

export const options = {
    plugins_off: {
        type: list<string>
        # chats and contacts stay on the phone, and nothing on it drives this machine
        default: $PLUGINS_GOVERNED
        choices: $PLUGINS_GOVERNED
        doc: ("KDE Connect plugins turned off for every paired device on each apply; drop one to use it (phone "
            + "notifications, SMS, the phone as remote or presenter)")
        label: "Plugins off"
        apply: relink
        scope: user
    }
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
    let plugins = {Plugins: ($PLUGINS_GOVERNED | each {|p| {$"($p)Enabled": ($p not-in $cfg.plugins_off | into string)} } | into record)}
    [
        (link-commands scripts/phone.nu)
        ($ids | each {|id| ini-merge ($config | path join $id $CLIPBOARD_PLUGIN config) $clipboard })
        ($ids | each {|id| ini-merge ($config | path join $id config) $plugins --then (device-plugins-reload $id) })
    ]
}
