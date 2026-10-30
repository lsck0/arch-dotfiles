# GOPATH moved from ~/.go to ~/.local/share/go, and base/xdg no longer links ~/.go there. A real ~/.go left by the old
# pam_env GOPATH moves to the new one once; base/xdg's next apply removes the link it made.

use module.nu [xdg]

export def up []: nothing -> nothing {
    let old = $nu.home-dir | path join .go
    let new = xdg data go
    if ($old | path type) == dir and not ($new | path exists) { mv $old $new }
}
