# desktop/konsole is gone. A deleted module never plans its own removals, so its records and what they name go here:
# the link into the wallust cache, the theme verb's profile (only while unchanged), konsolerc while it holds only the
# key dot merged, and the colorscheme wallust rendered into the cache.

use module.nu [xdg]
use state.nu [state-dir]

const MODULE = "desktop/konsole"
const KONSOLERC_MERGED = "[Desktop Entry]\nDefaultProfile=pywal.profile"

export def up []: nothing -> nothing {
    let records = state-dir | path join modules $MODULE
    if ($records | path exists) {
        let outputs = glob ($records | path join "*.nuon") | each { open $in | get outputs } | flatten
        for o in ($outputs | where kind == link) {
            if ($o.target | path type) == symlink and (ls -l $o.target | get 0.target) == $o.source { rm $o.target }
        }
        for o in ($outputs | where kind == file) {
            if ($o.target | path type) == file and (open --raw $o.target | hash sha256) == $o.hash { rm $o.target }
        }
        rm --recursive $records
    }
    let konsolerc = xdg config konsolerc
    if ($konsolerc | path exists) and (open --raw $konsolerc | str trim) == $KONSOLERC_MERGED { rm $konsolerc }
    rm --force (xdg cache wal colors-konsole.colorscheme)
    let data = xdg data konsole
    if ($data | path exists) and (ls --all $data | is-empty) { rm $data }
}
