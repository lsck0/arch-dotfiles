use module.nu *

export const meta = {reads: [desktop/hyprland], packages: {pacman: [gparted]}}

const WRAPPER = "/usr/local/bin/gparted-run"
const ACTION = "dev.lsck0.gparted.run"
const POLICY = "dev.lsck0.gparted.policy"

# root's detect sees no live Hyprland and falls back to the form factor's scale: the user layer, which sees the
# session's, hands it to the wrapper as its first argument
export def link [cfg: record] {
    desktop-exec gparted.desktop /usr/bin/gparted --command pkexec --args [$WRAPPER (xwayland-scale-for $cfg | into string)]
}

export def system [cfg: record] {
    let names = {ACTION: $ACTION, WRAPPER: $WRAPPER}
    [
        (file-render scripts/gparted-run.sh $WRAPPER {SCALE: (xwayland-scale-for $cfg)} --mode 755)
        (file-render $"config/($POLICY)" ("/usr/share/polkit-1/actions" | path join $POLICY) $names)
        (polkit-rules config/49-gparted.rules --values $names)
    ]
}
