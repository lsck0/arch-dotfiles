use module.nu *
use ../../base/bootvine/mod.nu [CONSOLE_PALETTE palette-channels]

export const meta = {packages: {pacman: [ly]}}

export const options = {
    autologin_after_unlock: {
        type: bool
        default: false
        doc: "Start the machine's one login without asking, once per boot: the LUKS passphrase just typed stands in for the login password and unlocks the keyring, so the two have to be equal. Whoever unlocks the disk, over remote-unlock's ssh too, leaves an open session at the console"
        label: "Login after disk unlock"
        apply: reboot
    }
}

const ETC = "/etc/ly"
const SESSIONS = $ETC | path join sessions
const SAVE = $ETC | path join save.txt
const LANG_STOCK = $ETC | path join lang en.ini
const HYPRLAND = "Hyprland"
const UID_MIN = 1000
const UID_MAX = 59999
const NO_LOGIN = '(nologin|false)$'
# ly puts one space between key hints; no-break spaces widen the gap, the ini parser trims plain ones
const HINT_GAP = "\u{a0}\u{a0}\u{a0}"
const AUTOLOGIN_STOCK = "/etc/pam.d/ly-autologin"
const AUTOLOGIN_SERVICE = "ly-unlocked"
const AUTOLOGIN_SESSION = "hyprland"
const LOADKEY_LINE = "-auth      optional     pam_systemd_loadkey.so"
const KEYRING_AUTH = '^-?auth\s.*pam_gnome_keyring[.]so'
const HINT_KEYS = '^(shutdown|restart|sleep|hibernate|toggle_password|brightness_down|brightness_up) = '

# The stock en lang with F4's hint renamed to reboot-to-firmware, so a ly update keeps the rest in step.
def lang-render []: nothing -> string {
    open --raw $LANG_STOCK | lines | each {|line|
        let line = if ($line | str starts-with "hibernate = ") { "hibernate = reboot to firmware" } else { $line }
        if $line =~ $HINT_KEYS { $"($line)($HINT_GAP)" } else { $line }
    } | to text
}

def logins []: nothing -> list<string> {
    open /etc/passwd | lines | split column ":" name x uid gid gecos home shell
    | where {|u| ($u.uid | into int) in $UID_MIN..$UID_MAX and $u.shell !~ $NO_LOGIN } | get name
}

# ly's own autologin stack with the cached disk passphrase handed to the keyring module; the package's file stays its.
export def autologin-pam [lines: list<string>]: nothing -> string {
    let at = $lines | enumerate | where {|l| $l.item =~ $KEYRING_AUTH } | get --optional 0.index | default ($lines | length)
    ($lines | first $at) ++ [$LOADKEY_LINE] ++ ($lines | skip $at) | to text
}

def autologin [cfg: record]: nothing -> record {
    let off = {config: "", decls: []}
    if not $cfg.autologin_after_unlock { return $off }
    let users = logins
    if ($users | length) != 1 { error make {msg: $"ly: autologin_after_unlock needs exactly one login, found ($users | length)"} }
    if not ($AUTOLOGIN_STOCK | path exists) { return $off }
    {
        config: $"\nauto_login_service = ($AUTOLOGIN_SERVICE)\nauto_login_session = ($AUTOLOGIN_SESSION)\nauto_login_user = ($users.0)\n"
        decls: [(file-text $"/etc/pam.d/($AUTOLOGIN_SERVICE)" (autologin-pam (open --raw $AUTOLOGIN_STOCK | lines))) (dropin ly@.service keyring.conf)]
    }
}

export def system [cfg: record] {
    let autologin = autologin $cfg
    let sessions = [sessions/hyprland.desktop sessions/plasma.desktop]
    let foreign = if ($SESSIONS | path exists) { ls $SESSIONS | get name | where ($it | path basename) not-in ($sessions | path basename) } else { [] }
    [
        # ly starts before /home is mounted, so every file is a real one in /etc
        (file-text ($ETC | path join config.ini) $"(open --raw config.ini)($autologin.config)")
        $autologin.decls
        (if ($LANG_STOCK | path exists) { file-text ($ETC | path join lang lsck0.ini) (lang-render) })
        (if ($foreign | is-not-empty) { exec "foreign sessions" [rm --force ...$foreign] })
        (files-into $SESSIONS ...$sessions)
        (step save-defaults)
        (file-text ($ETC | path join vtrgb) (palette-channels $CONSOLE_PALETTE | to text))
        ([palette.conf cursor.conf stage.conf log-filter.conf] | each { dropin ly@.service $in })
        (unit-enable ly@tty1.service)
        (unit-disable getty@tty1.service)
    ]
}

# Seeds Hyprland for users ly has not seen yet; ly keeps the known rows current itself (save=true).
export def save-defaults []: nothing -> nothing {
    # ly 1.4.1 lists its shell at 0, then the sessions in readdir order (no sort), so -U as ly does
    let names = ^ls -U $SESSIONS | lines
    let index = $names | enumerate | where {|s| open --raw ($SESSIONS | path join $s.item) | lines | any { $in == $"Name=($HYPRLAND)" } }
        | get --optional 0.index | default 0 | $in + 1
    let rows = if ($SAVE | path exists) { open --raw $SAVE | lines } else { ["1"] }
    let known = $rows | skip 1 | each { split row ":" | first }
    let added = ["root"] ++ (logins) | where $it not-in $known | each { $"($in):($index)" }
    $rows ++ $added | to text | save --force $SAVE
    ^chmod 644 $SAVE
}
