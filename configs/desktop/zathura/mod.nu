use module.nu *
use ../../core/wallust/font.nu [font-load]

# zathurarc's synctex-editor-command runs sioyek's synctex-edit
export const meta = {deps: [latex/sioyek], packages: {pacman: [zathura zathura-pdf-mupdf]}}

# zathurarc carries the font, so the theme verb writes it
export def link [cfg: record] { [] }

export def theme [cfg: record, wallpaper: string] {
    let font = font-load
    let dest = xdg config zathura zathurarc
    [
        (file-render zathurarc $dest {CACHE: (xdg cache), FONT: $font.family, UI_SIZE: $font.ui_size} --generated)
        (step config-source)
    ]
}

export def config-source []: nothing -> nothing {
    let names = do { ^gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames } | complete
    if $names.exit_code != 0 { return }
    $names.stdout | parse --regex "'(?<name>org\\.pwmt\\.zathura\\.PID-[0-9]+)'" | get name | each {|name|
        do { ^timeout 5 gdbus call --session --dest $name --object-path /org/pwmt/zathura --method org.pwmt.zathura.SourceConfig } | complete
    } | ignore
}
