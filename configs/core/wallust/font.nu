# The font as a theme input: $XDG_CACHE_HOME/wal/font.json, rendered by each module's theme verb.

use ../../../scripts/lib/state.nu [xdg]

const FILE = "wal/font.json"
const FONT_DEFAULT = {family: "Kode Mono", size: 13, ui_size: 11}
# a family without monospace glyphs takes this partner where the program needs a fixed pitch (terminals, editors)
const MONO_PARTNERS = {Tektur: "Kode Mono"}
const UI_SIZE_BASE = 10

def font-file []: nothing -> path { xdg cache $FILE }

def installed []: nothing -> list<string> {
    if (which fc-list | is-empty) { return [] }
    ^fc-list : family | lines | split row "," | str trim | compact --empty | uniq
}

# family, size and ui_size as set, plus mono (the fixed-pitch family) and scale (ui_size over gtk's base size)
export def font-load []: nothing -> record {
    let set = try { open (font-file) } catch { {} }
    let font = $FONT_DEFAULT | merge ($set | select --optional family size ui_size | compact)
    let partner = $MONO_PARTNERS | get --optional $font.family
    let mono = if $partner != null and $partner in (installed) { $partner } else { $font.family }
    $font | insert mono $mono | insert scale ($font.ui_size / $UI_SIZE_BASE | math round --precision 2)
}

# Written resolved (mono, scale) so readers without fc-list (nvim) take it as is.
export def font-save [changes: record]: nothing -> nothing {
    let file = font-file
    let set = try { open $file } catch { {} } | select --optional family size ui_size | compact
    mkdir ($file | path dirname)
    $set | merge $changes | save --force $file
    font-load | to json | save --force $file
}
