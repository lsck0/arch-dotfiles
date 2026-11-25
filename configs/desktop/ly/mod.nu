use module.nu *
use ../../base/bootvine/mod.nu [CONSOLE_PALETTE palette-channels]

# core/locale's language picks the greeter's
export const meta = {packages: {pacman: [ly]}, reads: [core/locale]}

export const options = {
    clock: {
        type: string?
        default: "%H:%M:%S"
        doc: "The greeter's clock, a strftime format; unset, no clock"
        label: "Login clock"
    }
    session: {
        type: string
        default: "Hyprland"
        choices: [Hyprland Plasma]
        doc: "Session preselected for a user ly has not seen yet; ly remembers each user's last one"
        label: "Default session"
    }
}

const ETC = "/etc/ly"
const SESSIONS = $ETC | path join sessions
const SAVE = $ETC | path join save.txt
const LANG_DIR = $ETC | path join lang
const LANG_FALLBACK = "en"
const UID_MIN = 1000
const UID_MAX = 59999
const NO_LOGIN = '(nologin|false)$'
# ly puts one space between key hints; no-break spaces widen the gap, the ini parser trims plain ones
const HINT_GAP = "\u{a0}\u{a0}\u{a0}"
const HINT_KEYS = '^(shutdown|restart|sleep|hibernate|toggle_password|brightness_down|brightness_up) = '

# ly's own lang file for a LANG (de_DE.UTF-8: de_DE.ini, else de.ini), else the english one.
def lang-stock [lang: any]: nothing -> path {
    let code = $lang | default "" | split row "." | first
    [$code ($code | split row "_" | first)] | where $it != "" | each { $LANG_DIR | path join $"($in).ini" }
        | where { path exists } | get --optional 0 | default ($LANG_DIR | path join $"($LANG_FALLBACK).ini")
}

# The stock lang with F4's hint renamed to reboot-to-firmware (added where a translation lacks it), so a ly update
# keeps the rest in step.
def lang-render [stock: path]: nothing -> string {
    let lines = open --raw $stock | lines
    let lines = if ($lines | any { str starts-with "hibernate = " }) { $lines } else { $lines | append "hibernate = " }
    $lines | each {|line|
        let line = if ($line | str starts-with "hibernate = ") { "hibernate = reboot to firmware" } else { $line }
        if $line =~ $HINT_KEYS { $"($line)($HINT_GAP)" } else { $line }
    } | to text
}

export def system [cfg: record] {
    let sessions = [config/sessions/hyprland.desktop config/sessions/plasma.desktop]
    let stock = lang-stock $cfg.deps?."core/locale"?.lang?
    let foreign = if ($SESSIONS | path exists) { ls $SESSIONS | get name | where ($it | path basename) not-in ($sessions | path basename) } else { [] }
    [
        # ly starts before /home is mounted, so every file is a real one in /etc
        (file-render config/config.ini ($ETC | path join config.ini) {CLOCK: ($cfg.clock | default "null")})
        (if ($stock | path exists) { file-text ($LANG_DIR | path join lsck0.ini) (lang-render $stock) })
        (if ($foreign | is-not-empty) { exec "foreign sessions" [rm --force ...$foreign] })
        (files-into $SESSIONS ...$sessions)
        (step save-defaults $cfg.session)
        (file-text ($ETC | path join vtrgb) (palette-channels $CONSOLE_PALETTE | to text))
        (unit-file services/ly.service)
        ([palette.conf cursor.conf stage.conf log-filter.conf shutdown.conf] | each { dropin ly.service $"services/($in)" })
        (unit-disable ly@tty1.service)
        (unit-enable ly.service)
        (unit-disable getty@tty1.service)
    ]
}

# Seeds the session for users ly has not seen yet; ly keeps the known rows current itself (save=true).
export def save-defaults [session: string]: nothing -> nothing {
    # ly 1.4.1 lists its shell at 0, then the sessions in readdir order (no sort), so -U as ly does
    let names = ^ls -U $SESSIONS | lines
    let index = $names | enumerate | where {|s| open --raw ($SESSIONS | path join $s.item) | lines | any { $in == $"Name=($session)" } }
        | get --optional 0.index | default 0 | $in + 1
    let rows = if ($SAVE | path exists) { open --raw $SAVE | lines } else { ["1"] }
    let known = $rows | skip 1 | each { split row ":" | first }
    let users = open /etc/passwd | lines | split column ":" name x uid gid gecos home shell
        | where {|u| ($u.uid | into int) in $UID_MIN..$UID_MAX and $u.shell !~ $NO_LOGIN } | get name
    let added = ["root"] ++ $users | where $it not-in $known | each { $"($in):($index)" }
    $rows ++ $added | to text | save --force $SAVE
    ^chmod 644 $SAVE
}
