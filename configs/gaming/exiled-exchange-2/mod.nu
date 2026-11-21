use module.nu *

# Path of Exile 2's price check overlay; it finds Steam's PoE 2 log and Proton config by itself
export const meta = {packages: {pacman: [exiled-exchange-2-bin]}}

const DESKTOP = "exiled-exchange-2.desktop"

export def link [cfg: record] {
    # an AppImage's Exec=AppRun is not on PATH, so gtk-launch and the launcher refuse the entry
    desktop-override $DESKTOP {
        let entry = $in
        if ($entry =~ '(?m)^Exec=AppRun') { $entry | desktop-set {Exec: "exiled-exchange-2 %U"} } else { $entry }
    }
}
