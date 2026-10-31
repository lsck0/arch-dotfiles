use module.nu *

export const meta = {packages: {pacman: [elan-lean lean-tui]}}

const ELAN = "/usr/bin/elan"
const CHANNEL = "nightly"

export def link [cfg: record] {
    if not ($ELAN | path exists) { return [] }
    let home = $env.ELAN_HOME? | default ($nu.home-dir | path join .elan)
    let installed = glob ($home | path join toolchains $"leanprover--lean4-($CHANNEL)---*") | is-not-empty
    let current = try { open ($home | path join settings.toml) | get default_toolchain } catch { null }
    [
        (if $installed { [] } else { [(exec elan-install [$ELAN toolchain install $CHANNEL] --network)] })
        (if $current == $CHANNEL { [] } else { [(exec elan-default [$ELAN default $CHANNEL])] })
    ]
}
