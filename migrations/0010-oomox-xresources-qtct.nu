# desktop/oomox no longer exports Xresources or qt5ct/qt6ct colors, and base/xdg no longer links ~/.Xcolours; what
# those exports left goes.

use module.nu [xdg]

export def up []: nothing -> nothing {
    let link = $nu.home-dir | path join .Xcolours
    if ($link | path type) == symlink { rm $link }
    rm --force --recursive (xdg config Xcolours)
    for tool in [qt5ct qt6ct] {
        rm --force (xdg config $tool colors oomox-colors-oomox.conf)
        for dir in [(xdg config $tool colors) (xdg config $tool)] {
            if ($dir | path type) == dir and (ls --all $dir | is-empty) { rm $dir }
        }
    }
}
