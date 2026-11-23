#!/usr/bin/env -S nu --no-config-file
# gtk4.css renders with every placeholder filled: prettier once split @RADIUS_PX@px into @RADIUS_PX @px, which
# file-render never matches, and the window radius stayed unset.
use module.nu [file-render]

const HERE = path self .

use std/assert

def main [] {
    let css = file-render ($HERE | path join gtk4.css) /nonexistent/gtk.css {THEME_CSS: /theme.css, RADIUS_PX: 2} | get content
    let left = $css | parse --regex '(?P<p>@[A-Z_]+@?)' | get p
    assert equal $left [] "placeholders left"
    assert ($css | str contains "--window-radius: 2px;") "--window-radius is not 2px"
}
