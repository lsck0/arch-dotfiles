use module.nu *
use ../../base/bootvine/mod.nu [CONSOLE_PALETTE palette-channels]

export const meta = {packages: {pacman: [ly]}}

const ETC = "/etc/ly"
const SESSIONS = "/etc/ly/sessions"
const SAVE = "/etc/ly/save.txt"
const LANG_STOCK = "/etc/ly/lang/en.ini"
const HYPRLAND = "Hyprland"
const UID_MIN = 1000
const UID_MAX = 59999
const NO_LOGIN = '(nologin|false)$'
# ly puts one space between key hints; no-break spaces widen the gap, the ini parser trims plain ones
const HINT_GAP = "\u{a0}\u{a0}\u{a0}"
const HINT_KEYS = '^(shutdown|restart|sleep|hibernate|toggle_password|brightness_down|brightness_up) = '

# The stock en lang with F4's hint renamed to reboot-to-firmware, so a ly update keeps the rest in step.
def lang-render []: nothing -> string {
    open --raw $LANG_STOCK | lines | each {|line|
        let line = if ($line | str starts-with "hibernate = ") { "hibernate = reboot to firmware" } else { $line }
        if $line =~ $HINT_KEYS { $"($line)($HINT_GAP)" } else { $line }
    } | str join "\n" | $"($in)\n"
}

export def system [cfg: record] {
    let sessions = [sessions/hyprland.desktop sessions/plasma.desktop]
    let foreign = if ($SESSIONS | path exists) { ls $SESSIONS | get name | where ($it | path basename) not-in ($sessions | path basename) } else { [] }
    [
        # ly starts before /home is mounted, so every file is a real one in /etc
        (file-copy config.ini ($ETC | path join config.ini))
        (if ($LANG_STOCK | path exists) { file-text ($ETC | path join lang lsck0.ini) (lang-render) })
        (if ($foreign | is-not-empty) { exec "foreign sessions" [rm --force ...$foreign] })
        (files-into $SESSIONS ...$sessions)
        (step save-defaults)
        (file-text ($ETC | path join vtrgb) (palette-channels $CONSOLE_PALETTE | str join "\n" | $"($in)\n"))
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
    let users = open /etc/passwd | lines | split column ":" name x uid gid gecos home shell
        | where {|u| ($u.uid | into int) in $UID_MIN..$UID_MAX and $u.shell !~ $NO_LOGIN } | get name
    let added = ["root"] ++ $users | where $it not-in $known | each { $"($in):($index)" }
    $rows ++ $added | str join "\n" | $"($in)\n" | save --force $SAVE
    ^chmod 644 $SAVE
}
