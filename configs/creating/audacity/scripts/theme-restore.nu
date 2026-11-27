#!/usr/bin/env -S nu --no-config-file
# audacity rewrites its whole cfg from memory on exit, GUI/Theme as it started included: puts the palette's back

use ../../../../scripts/lib/state.nu [state-dir state-locked xdg]
use ../../../core/wallust/scripts/palette.nu [palette-load]

# The GUI/Theme the palette in effect wants.
export def audacity-theme []: nothing -> string {
    if (palette-load | get --optional light) == "1" { "light" } else { "dark" }
}

# Under the lock dot's own ini merges take; a value already in place writes nothing, so the watch does not loop.
def main []: nothing -> nothing {
    let cfg = xdg config audacity audacity.cfg
    if not ($cfg | path exists) { return }
    let edits = [{values: {GUI: {Theme: (audacity-theme)}}, missing_only: false}]
    state-locked $"(state-dir)/json.lock" ini-update {file: $cfg, edits: $edits} | ignore
}
