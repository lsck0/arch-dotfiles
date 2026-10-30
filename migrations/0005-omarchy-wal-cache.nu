# core/wallust's omarchy palette left templates/wal/, so the wal/ render no longer writes it into the cache; the copy
# it wrote there goes.

use module.nu [xdg]

export def up []: nothing -> nothing {
    rm --force (xdg cache wal omarchy-colors.toml)
}
