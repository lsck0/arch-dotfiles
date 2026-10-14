use module.nu *

export const meta = {packages: {pacman: [ly]}}

const ETC = "/etc/ly"
const SESSIONS = "/etc/ly/sessions"
const SAVE = "/etc/ly/save.txt"
const LANG_STOCK = "/etc/ly/lang/en.ini"
const HYPRLAND = "Hyprland"
# login.defs' human uid range; build users (nixbld) in it have no login shell
const UID_MIN = 1000
const UID_MAX = 59999
const NO_LOGIN = '(nologin|false)$'
# ly puts one space between key hints; trailing no-break spaces (the ini parser trims plain ones) widen the gap
const HINT_GAP = "\u{a0}\u{a0}\u{a0}"
const HINT_KEYS = '^(shutdown|restart|sleep|hibernate|toggle_password|brightness_down|brightness_up) = '
# config.ini's exact hex; the console maps ly's 24-bit colours to these 16 slots
const PALETTE = [
    "0b0e14" f07178 aad94c e6b450 "39bae6" d2a6ff "1c6e8c" bfbdb6
    "565b66" f07178 aad94c e6b450 "39bae6" d2a6ff "39bae6" bfbdb6
]

# the stock en lang with F4's hint renamed to reboot-to-firmware, so a ly update keeps the rest in step
def lang-render []: nothing -> string {
    open --raw $LANG_STOCK | lines | each {|line|
        let line = if ($line | str starts-with "hibernate = ") { "hibernate = reboot to firmware" } else { $line }
        if $line =~ $HINT_KEYS { $"($line)($HINT_GAP)" } else { $line }
    } | str join "\n" | $"($in)\n"
}

# setvtrgb's format: one line each of the reds, greens and blues
def vtrgb-render []: nothing -> string {
    [0 2 4] | each {|at| $PALETTE | each { $"0x($in | str substring $at..($at + 1))" | into int } | str join "," } | str join "\n" | $"($in)\n"
}

# ly runs at boot before /home is mounted, so every file is a real one in /etc
export def system [cfg: record] {
    let sessions = [sessions/hyprland.desktop sessions/plasma.desktop]
    let foreign = if ($SESSIONS | path exists) { ls $SESSIONS | get name | where ($it | path basename) not-in ($sessions | path basename) } else { [] }
    [
        (file-copy config.ini ($ETC | path join config.ini))
        (if ($LANG_STOCK | path exists) { file-text ($ETC | path join lang lsck0.ini) (lang-render) } else { [] })
        # only Hyprland (uwsm) and Plasma show, next to ly's built-in shell
        (if ($foreign | is-empty) { [] } else { exec "foreign sessions" [rm --force ...$foreign] })
        (files-into $SESSIONS ...$sessions)
        (step save-defaults)
        (file-text ($ETC | path join vtrgb) (vtrgb-render))
        (dropin ly@.service palette.conf)
        (dropin ly@.service cursor.conf)
        (unit-enable ly@tty2.service)
        (unit-disable getty@tty2.service)
    ]
}

# ly keeps known rows current (save=true); a user it has not seen yet defaults to Hyprland
export def save-defaults []: nothing -> nothing {
    # ly 1.4.1 lists its shell at 0, then crawls the sessions in readdir order (no sort), so -U as ly will
    let names = ^ls -U $SESSIONS | lines
    let index = $names | enumerate | where {|s| open --raw ($SESSIONS | path join $s.item) | lines | any { $in == $"Name=($HYPRLAND)" } }
        | get --optional 0.index | default 0 | $in + 1
    let rows = if ($SAVE | path exists) { open --raw $SAVE | lines } else { ["1"] }
    let known = $rows | skip 1 | each { split row ":" | first }
    let users = open /etc/passwd | lines | split column ":" name x uid gid gecos home shell
        | where {|u| ($u.uid | into int) in $UID_MIN..$UID_MAX and $u.shell !~ $NO_LOGIN } | get name
    let added = ["root"] ++ $users | where $it not-in $known | each { $"($in):($index)" }
    $rows ++ $added | str join "\n" | $"($in)\n" | save --force $SAVE
    ^chmod 644 $SAVE
}
