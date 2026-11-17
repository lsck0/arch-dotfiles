# millennium 3.6.3_beta.1 sorts above the 3.6.3 release (vercmp), so -Su never replaces it, and only the release has the
# x64 bootstrap steam's steamrt64 client loads: the theme stayed off
export const layer = "system"

export def up []: nothing -> nothing {
    let installed = ^pacman -Q millennium | complete
    if $installed.exit_code != 0 or not ($installed.stdout | str contains "_beta") { return }
    ^pacman -S --noconfirm millennium
}
