# vim.pack left an empty site/pack/core/opt behind, which lazy's checkhealth warns about; only empty dirs go.

use module.nu [xdg]

export def up []: nothing -> nothing {
    let pack = xdg data nvim site pack
    for dir in [($pack | path join core opt) ($pack | path join core) $pack] {
        if ($dir | path type) == dir and (ls --all $dir | is-empty) { rm $dir }
    }
}
