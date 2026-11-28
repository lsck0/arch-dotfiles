#!/usr/bin/env -S nu --no-config-file
# config/mods/wallust-look builds a Claude Desktop look from each theme's palette: every one must be a look Desktop paints

const HERE = path self .

def main [] {
    let mod = $HERE | path join config mods wallust-look hooks register.ts
    let check = $HERE | path join test look-paints.mjs
    let themes = $HERE | path join .. .. .. themes
    ^node --experimental-strip-types --no-warnings $check $mod $themes
}
