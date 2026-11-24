use module.nu *

export const meta = {packages: {pacman: [jetbrains-toolbox]}}

export const options = {
    autostart: {type: bool, default: false, doc: "Toolbox starts with the session", label: "Autostart"}
}

export def link [cfg: record] {
    # toolbox rewrites its autostart entry on every start, so the generated unit is masked
    if not $cfg.autostart { unit-mask "app-jetbrains\\x2dtoolbox@autostart.service" }
}
