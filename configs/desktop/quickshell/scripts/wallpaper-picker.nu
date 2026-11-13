#!/usr/bin/env -S nu --no-config-file
# opens the quickshell image picker, which runs `dot theme <image>` on Enter; without quickshell, a bemenu picker: the
# keybind runs this without a terminal, where dot's fzf picker cannot draw

const HERE = path self | path expand | path dirname
use ($HERE | path join lib shell.nu) [shell-call]

const MENU = ($HERE | path join .. .. hyprland picker.nu | path expand)
const THEME_LIST = ($HERE | path join .. plugins image-picker list.nu | path expand)
const WALLPAPER_LIST = ($HERE | path join .. .. .. core wallust wallpaper-list.nu | path expand)
const THEME_DIR = ($HERE | path join .. .. .. .. themes | path expand)

def dot-bin []: nothing -> path { $nu.home-dir | path join .local bin dot }

# {label, image} per choice: a theme by name (its wallpaper is the theme), a wallpaper by file name
def choices-list [themes: bool]: nothing -> table<label: string, image: string> {
    if $themes {
        ^$THEME_LIST themes $THEME_DIR $WALLPAPER_LIST | lines | split column "\t" image thumb label | select label image
    } else {
        ^(dot-bin) internal theme list | lines | where $it != "" | each {|f| {label: ($f | path basename), image: $f} }
    }
}

def fallback-pick [themes: bool]: nothing -> nothing {
    let choices = choices-list $themes
    let picked = $choices.label | str join "\n" | ^$MENU -p (if $themes { "theme" } else { "wallpaper" }) | complete
    let label = $picked.stdout | str trim
    if $picked.exit_code != 0 or $label == "" { return }
    let image = $choices | where label == $label | get 0?.image
    if $image != null { ^(dot-bin) theme $image }
}

def main [--themes] {
    let payload = {
        mode: (if $themes { 1 } else { 0 })
        selectedImage: ($env.XDG_CACHE_HOME? | default ($nu.home-dir | path join .cache) | path join wal wallpaper | path expand)
    }
    # summon exits 0 with "unknown" when the plugin failed to load, so only "ok" means a picker is open
    let summoned = shell-call shell summon panel.image-picker ($payload | to json -r) | complete
    if not ($summoned.stdout =~ ok) {
        print -e "quickshell picker unavailable; falling back to bemenu"
        fallback-pick $themes
    }
}
