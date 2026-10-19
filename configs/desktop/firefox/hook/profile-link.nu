#!/usr/bin/env -S nu --no-config-file
# a profile firefox made itself (a downgrade, about:profiles) has no user.js or userChrome.css until desktop/firefox
# links it; a profiles.ini change with every profile styled is left alone

# the unit's environment has no DOTFILES outside a uwsm session
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
