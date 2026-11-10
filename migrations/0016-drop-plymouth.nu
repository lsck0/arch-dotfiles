# base/plymouth became base/bootvine: plymouth leaves HOOKS before its package does, since base/bootvine's own drop
# waits for the bootvine package and a hook without its install script fails every mkinitcpio.

use ../configs/base/boot/boot.nu [MKINITCPIO hooks-read hooks-write cmdline-unset]

export const layer = "system"

export def up []: nothing -> nothing {
    if not ($MKINITCPIO | path exists) { return }
    hooks-write (hooks-read | where $it != plymouth)
    cmdline-unset splash
}
