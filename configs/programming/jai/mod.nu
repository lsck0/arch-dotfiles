use module.nu *
use hook/jai-install.nu [zip-newest]

export const meta = {
    packages: {pacman: [unzip]}
    inputs: [~/sync/vendor ~/.jai/.installed-from]
}

const HOOK = "hook/jai-install.nu"

export def link [cfg: record] {
    if not (owner-unlocked) {
        if (profile-has secrets) { log-warn "jai: secrets locked" }
        return []
    }
    let dir = $nu.home-dir | path join .jai
    if not ($dir | path join bin jai-linux | path exists) {
        # no --mkdir: a dir made in ~/sync before syncthing delivers its own can collide
        return (user-hook jai-install $HOOK --watch ["%h/sync/vendor"])
    }
    let zip = zip-newest
    let stamp = file-trim ($dir | path join .installed-from)
    let newer = $zip != null and ($zip | path basename) != $stamp
    let current = not $newer and ($dir | path join bin jai | path exists)
    [(exec jai-install [($env.PWD | path join $HOOK)] --done=$current --network)]
}
