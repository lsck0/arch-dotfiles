#!/usr/bin/env -S nu --no-config-file
# links a profile firefox made itself; the unit has no DOTFILES outside a uwsm session

const DOT = path self | path dirname | path join .. .. .. .. scripts dot.nu

def main []: nothing -> nothing {
    let ini = $nu.home-dir | path join .config mozilla firefox profiles.ini
    if not ($ini | path exists) { return }
    let bare = open --raw $ini | lines | parse "Path={path}" | get path
        | each {|p| $ini | path dirname | path join $p }
        | where {|dir| ($dir | path exists) and not ($dir | path join user.js | path exists) }
    if ($bare | is-empty) { return }
    ^$DOT apply --user desktop/firefox
}
