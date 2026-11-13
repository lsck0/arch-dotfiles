# programming/emacs is Doom now: a pinned checkout in ~/.config/emacs, the config in $DOOMDIR. Before the checkout
# lands, the former config moves aside, since Doom's own early-init.el collides with it. The package, native-compile,
# grammar and package-vc caches it filled go; Doom keeps its own under .local/.

use module.nu [xdg]
use preserve.nu [preserve-aside]

const DOOM_BIN = "bin/doom"
const CONFIG_LISP = "*.el"
const CONFIG_OTHER = [templates.eld formatting]
const CACHES = [elpa eln-cache tree-sitter]
const SOURCES = "sources"

export def up []: nothing -> nothing {
    let dir = xdg config emacs
    if not ($dir | path exists) { return }
    let doom = $dir | path join $DOOM_BIN | path exists
    if not $doom {
        for path in (glob ($dir | path join $CONFIG_LISP) | append ($CONFIG_OTHER | each {|name| $dir | path join $name })) {
            preserve-aside $path
        }
    }
    for name in $CACHES { rm --recursive --force ($dir | path join $name) }
    let sources = $dir | path join $SOURCES
    if not ($sources | path exists) { return }
    # sources/doom+ is Doom's own submodule
    let tracked = if $doom { ^git -C $dir ls-files $SOURCES | lines | each {|path| $path | path split | first 2 | path join } } else { [] }
    for path in (ls --all $sources | get name | where ($it | path relative-to $dir) not-in $tracked) {
        rm --recursive --force $path
    }
}
