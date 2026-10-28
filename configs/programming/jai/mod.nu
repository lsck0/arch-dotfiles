use module.nu *
use hook/jai-install.nu [jai-zip]

export const meta = {inputs: [~/sync/vendor ~/.jai/.installed-from]}

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
    let zip = jai-zip
    let stamp = try { open --raw ($dir | path join .installed-from) | str trim } catch { "" }
    let newer = $zip != null and ($zip | path basename) != $stamp
    if $newer or not ($dir | path join bin jai | path exists) { [(exec jai-install [($env.PWD | path join $HOOK)])] } else { [] }
}
