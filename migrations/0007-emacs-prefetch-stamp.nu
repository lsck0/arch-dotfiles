# programming/emacs now checks elpa/ for missing packages instead of a stamp; the stamp it left there goes.

use module.nu [xdg]

export def up []: nothing -> nothing {
    rm --force (xdg config emacs elpa .dotfiles-prefetched)
}
