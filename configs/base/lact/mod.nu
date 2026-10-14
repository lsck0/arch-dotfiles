use module.nu *

export const meta = {packages: {native: [lact]}}

# lactd idles on its socket and changes nothing until a setting is applied in the gui
export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    unit-enable lactd.service --now
}
