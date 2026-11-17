#!/bin/sh
# gitk run with tk scaled to GDK_SCALE: its point fonts follow tk scaling, the pixel ones are multiplied \
exec wish "$0" -- "$@"

if {[info exists env(GDK_SCALE)]} {
    set scale $env(GDK_SCALE)
    tk scaling [expr {[tk scaling] * $scale}]
    foreach font [font names] {
        set size [font configure $font -size]
        if {$size < 0} { font configure $font -size [expr {round($size * $scale)}] }
    }
}
set argv0 /usr/bin/gitk
source $argv0
