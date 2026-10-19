use module.nu *

export const meta = {packages: {pacman: [zathura zathura-pdf-mupdf]}}

export def link [cfg: record] {
    file-render zathurarc ($nu.home-dir | path join .config zathura zathurarc) {HOME: $nu.home-dir}
}

# a running zathura rereads its config, the included palette with it, only when told over d-bus
export def theme [cfg: record, wallpaper: string] {
    step config-source
}

export def config-source []: nothing -> nothing {
    let names = do { ^gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus --method org.freedesktop.DBus.ListNames } | complete
    if $names.exit_code != 0 { return }
    $names.stdout | parse --regex "'(?<name>org\\.pwmt\\.zathura\\.PID-[0-9]+)'" | get name | each {|name|
        do { ^timeout 5 gdbus call --session --dest $name --object-path /org/pwmt/zathura --method org.pwmt.zathura.SourceConfig } | complete
    } | ignore
}
