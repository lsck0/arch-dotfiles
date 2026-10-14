use module.nu *
use hook/jai-install.nu [jai-zip]

export const meta = {inputs: [~/sync/vendor ~/.jai/.installed-from]}

const HOOK = "hook/jai-install.nu"

# the owner's jai beta, synced into ~/sync/vendor
export def link [cfg: record] {
    if not (profile-has identity) { return [] }
    let dir = $nu.home-dir | path join .jai
    if not ($dir | path join bin jai-linux | path exists) {
        # no --mkdir: a dir made in ~/sync before syncthing delivers its own can collide
        return (user-hook jai-install $HOOK --watch ["%h/sync/vendor"])
    }
    let zip = jai-zip
    let stamp = try { open --raw ($dir | path join .installed-from) | str trim } catch { "" }
    let newer = $zip != null and ($zip | path basename) != $stamp
    # a later beta installs here, without a watching unit
    if $newer or not ($dir | path join bin jai | path exists) { [(exec jai-install [($env.PWD | path join $HOOK)])] } else { [] }
}
