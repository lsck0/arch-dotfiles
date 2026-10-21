use module.nu *

export const meta = {packages: {pacman: [apalache-bin cbmc tla-toolbox z3]}}

# upstream's entry has Version=1.7 and an unregistered category "Formal Methods"
export def link [cfg: record] {
    desktop-override tla-toolbox.desktop {
        str replace --regex '(?m)^Version=.*$' "Version=1.5" | str replace --regex '(?m)^Categories=.*$' "Categories=Development;IDE;"
    }
}
