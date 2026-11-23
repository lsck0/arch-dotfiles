use module.nu *

# Path of Exile 2's price check overlay; it finds Steam's PoE 2 log and Proton config by itself. Its own pkgbuild
# (mirror/pkgbuilds) runs the AppImage's electron and ships a desktop entry that launches from PATH.
export const meta = {packages: {pacman: [exiled-exchange-2-bin]}}
