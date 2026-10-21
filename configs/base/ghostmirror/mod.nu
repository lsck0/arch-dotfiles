use module.nu *

export const meta = {packages: {pacman: [ghostmirror]}}

export const options = {
    homelab_mirror: {
        type: string?
        default: null
        doc: "A homelab pacman mirror's URL ($repo and $arch as in a mirrorlist), put first on a homelab machine"
        label: "Homelab mirror"
        scope: machine
    }
}

const MIRRORLIST = "/etc/pacman.d/mirrorlist"
const HOMELAB_FILE = "/etc/pacman.d/homelab-mirror"
const PROBE_TIMEOUT_S = 2
const RANK_TIMEOUT_S = 600
const HOMELAB_COMMENT = (
    "# homelab mirror: lan-direct at home and over wireguard, the public mirrors below are the away fallback"
)

export def system [cfg: record] {
    let homelab = if (platform-has homelab) and $cfg.homelab_mirror != null { $"Server=($cfg.homelab_mirror)" }
    [
        (file-copy mirrorlist-update.nu /usr/local/bin/mirrorlist-update --mode 755)
        (if $homelab != null { file-text $HOMELAB_FILE $"($homelab)\n" } else { [] })
        (step place)
        (unit-file ghostmirror.service)
        (unit-file ghostmirror.timer --enable --now)
        (unit-file ghostmirror-refresh.service)
        (unit-file ghostmirror-refresh.timer --enable --now)
    ]
}

def mirrorlist-swap [lines: list<string>]: nothing -> nothing {
    $lines | str join "\n" | $"($in)\n" | save --force $"($MIRRORLIST).new"
    ^mv -f $"($MIRRORLIST).new" $MIRRORLIST
}

def rank [mode: string]: nothing -> bool {
    (^timeout $RANK_TIMEOUT_S /usr/local/bin/mirrorlist-update $mode | complete).exit_code == 0
}

export def place []: nothing -> nothing {
    let linked = ($MIRRORLIST | path type) == "symlink"
    if $linked or not (open --raw $MIRRORLIST | lines | any { str starts-with "# lastsync" }) {
        if (rank rebuild) {
            rank sort | ignore
        } else if $linked or not (open --raw $MIRRORLIST | lines | any { str starts-with "Server" }) {
            mirrorlist-swap (open --raw mirrorlist | lines)
        }
    }
    let current = open --raw $MIRRORLIST | lines
    let homelab = try { open --raw $HOMELAB_FILE | str trim } catch { "" }
    if $homelab == "" {
        let drop = $current | enumerate | where {|l| $l.item | str starts-with "# homelab" }
            | each { [$in.index ($in.index + 1)] } | flatten
        if ($drop | is-not-empty) { mirrorlist-swap ($current | enumerate | where index not-in $drop | get item) }
    } else if $homelab not-in $current {
        let probe = $homelab | str replace "Server=" "" | str replace '$repo' core | str replace '$arch' x86_64
            | $"($in)/core.db"
        if (^curl -fs -m $PROBE_TIMEOUT_S -r 0-0 -o /dev/null $probe | complete).exit_code == 0 {
            mirrorlist-swap ([$HOMELAB_COMMENT $homelab ""] ++ $current)
        }
    }
}
