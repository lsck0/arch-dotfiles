# Root's half of 0001: the same fold of /var/lib/dotfiles/written into root's module records.

use state.nu [state-dir]
use 0001-state-records.nu [convert restore]

export const layer = "system"

export def up []: nothing -> nothing { convert (state-dir) }
export def down []: nothing -> nothing { restore (state-dir) }
