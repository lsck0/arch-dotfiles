use module.nu *

export const meta = {packages: {pacman: [downgrade pacman-contrib yay]}}

export const options = {
    yay_cache_days: {
        type: int
        default: 30
        doc: "Days an unused yay build cache dir may sit in ~/.cache/yay before yay-cache-clean.timer deletes it, find -mtime argument"
        label: "Yay cache retention (days)"
        scope: user
    }
}

const SNAPSHOT = '^(\d{4}-\d{2}-\d{2})?$'

export def system [cfg: record] {
    let snapshot = $env.LSCK0_SNAPSHOT? | default ""
    if not ($snapshot =~ $SNAPSHOT) { error make {msg: $"pacman: lsck0_snapshot '($snapshot)' is not YYYY-MM-DD"} }
    let suffix = if $snapshot == "" { "" } else { $"/($snapshot)" }
    let conf = open --raw pacman.conf | split row "\n" | reduce --fold {out: [], lsck0: false} {|l, acc|
        let lsck0 = if ($l | str starts-with "[") { $l == "[lsck0]" } else { $acc.lsck0 }
        let line = if $lsck0 { $l | str replace --regex '/\$arch$' $"($suffix)/$$arch" } else { $l }
        {out: ($acc.out | append $line), lsck0: $lsck0}
    } | get out | str join "\n"
    [
        (step trust)
        (file-text /etc/pacman.conf $conf)
        (files-into /etc/pacman.d/hooks ...(glob hooks/*.hook))
    ]
}

# Locally signs archrepo.asc's key, read in a throwaway gpg home so no /root/.gnupg stays behind.
export def trust []: nothing -> nothing {
    let home = mktemp --directory
    let fingerprint = ^gpg --homedir $home --show-keys --with-colons archrepo.asc | lines | parse "fpr:{rest}"
        | get --optional 0.rest | default "" | split row ":" | get --optional 8
    rm --recursive --force $home
    if ($fingerprint | is-empty) { error make {msg: "pacman: no fingerprint in archrepo.asc"} }
    ^pacman-key --add archrepo.asc
    ^pacman-key --lsign-key $fingerprint
}

export def link [cfg: record] {
    [
        (files-into (xdg config pacman) makepkg.conf)
        (file-render yay-cache-clean.service (unit-dir | path join yay-cache-clean.service) {CACHE_DAYS: $cfg.yay_cache_days})
        (unit-file yay-cache-clean.timer --enable --now)
    ]
}
