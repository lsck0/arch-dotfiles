# The user half of 0007: the profile's options file and the checkout's git-ignored platforms/local.options.nuon
use state.nu [xdg]
use platform.nu [PLATFORM_REPO_LOCAL]
use 0007-module-moves-root.nu [options-moved]

const REPO = path self ..

export def up []: nothing -> nothing {
    options-moved (xdg config dotfiles options.nuon)
    options-moved ($REPO | path join $PLATFORM_REPO_LOCAL.1)
}
