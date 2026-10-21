use module.nu *

export const meta = {packages: {native: [amdgpu_top lact]}}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    unit-enable lactd.service --now
}
