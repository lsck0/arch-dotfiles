# The flatpak ledger records app ids alone; entries written as `<app> <commit>` drop their commit.

use ledger.nu [ledger-get ledger-set]

export def up []: nothing -> nothing {
    ledger-set flatpak (ledger-get flatpak | each { split row " " | first } | uniq)
}
