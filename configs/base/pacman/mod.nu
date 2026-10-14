use module.nu *

export const meta = {packages: {pacman: [downgrade pacman-contrib yay]}}

const SNAPSHOT = '^(\d{4}-\d{2}-\d{2})?$'

# lsck0_snapshot pins [lsck0] to a dated snapshot; an unreachable one fails the sync instead of mixing sonames
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

# a throwaway keyring, so no /root/.gnupg stays behind
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
        (files-into ($nu.home-dir | path join .config pacman) makepkg.conf)
        (unit-file yay-cache-clean.service)
        (unit-file yay-cache-clean.timer --enable --now)
    ]
}
