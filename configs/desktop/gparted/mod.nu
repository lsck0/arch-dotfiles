use module.nu *

export const meta = {reads: [desktop/hyprland], packages: {pacman: [gparted]}}

const WRAPPER = "/usr/local/bin/gparted-run"
const ACTION = "dev.lsck0.gparted.run"
const POLICY = "dev.lsck0.gparted.policy"

# root's detect sees no live Hyprland and falls back to the form factor's scale: the user layer, which sees the
# session's, hands it to the wrapper as its first argument
export def link [cfg: record] {
    let scale = xwayland-scale-for $cfg
    desktop-override gparted.desktop {
        str replace --all --regex '(?m)^Exec=.*gparted.*$' $'Exec=pkexec ($WRAPPER) ($scale) %f'
    }
}

export def system [cfg: record] {
    let names = {ACTION: $ACTION, WRAPPER: $WRAPPER}
    [
        (file-render gparted-run.sh $WRAPPER {SCALE: (xwayland-scale-for $cfg)} --mode 755)
        (file-render $POLICY ("/usr/share/polkit-1/actions" | path join $POLICY) $names)
        (polkit-rules 49-gparted.rules --values $names)
    ]
}
