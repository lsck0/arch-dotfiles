use module.nu *

export const meta = {deps: [core/wallust], packages: {pacman: [btop]}}

export const options = {
    accent: {
        type: string
        default: c4
        doc: "Palette slot for titles, highlights and the selection"
        label: "Accent colour"
        choices: [c1 c2 c3 c4 c5 c6]
        apply: live
    }
}

const CONFIG_DIR = ".config/btop"

export def link [cfg: record] {
    files-into ($nu.home-dir | path join $CONFIG_DIR) btop.conf
}

export def apply [cfg: record] {
    theme $cfg ""
}

export def theme [cfg: record, wallpaper: string] {
    let p = palette-load
    if $p == null { return [] }
    let accent = $p | get $cfg.accent
    let slots = {
        main_bg: $p.bg main_fg: $p.fg title: $accent hi_fg: $accent selected_bg: $accent selected_fg: $p.bg
        inactive_fg: $p.c8 graph_text: $p.fg meter_bg: $p.c8 proc_misc: $p.c6
        cpu_box: $p.c4 mem_box: $p.c6 net_box: $p.c5 proc_box: $p.c2 div_line: $p.c8
        temp_start: $p.c2 temp_mid: $p.c3 temp_end: $p.c1
        cpu_start: $p.c4 cpu_mid: $p.c5 cpu_end: $p.c1
        free_start: $p.c2 free_mid: $p.c6 free_end: $p.c4
        used_start: $p.c3 used_mid: $p.c1 used_end: $p.c1
        available_start: $p.c6 available_mid: $p.c4 available_end: $p.c5
        cached_start: $p.c5 cached_mid: $p.c4 cached_end: $p.c6
        download_start: $p.c6 download_mid: $p.c4 download_end: $p.c5
        upload_start: $p.c5 upload_mid: $p.c1 upload_end: $p.c3
        process_start: $p.c4 process_mid: $p.c6 process_end: $p.c2
    }
    let text = $slots | items {|key, value| $'theme[($key)]="($value)"' } | str join "\n"
    file-text ($nu.home-dir | path join $CONFIG_DIR themes pywal.theme) $"($text)\n" --generated
}
