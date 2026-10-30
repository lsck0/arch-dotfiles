use module.nu *

export const meta = {
    packages: {
        pacman: [
            ani-cli-git bleachbit bluetui chawan filezilla font-manager gearlever geogebra-6-bin gnome-calculator
            gnome-calendar gnome-maps gnome-text-editor hollywood josm kdeconnect kleopatra linecast localsend
            logseq-desktop-bin lynx metadata-cleaner minder mov-cli mpg123 nemo okular onlyoffice-bin piper
            proton-authenticator-bin proton-pass-bin proton-vpn-qt-app snapshot sowon-git stirling-pdf-bin tlpui
            torbrowser-launcher waypipe wev wine-staging xorg-xeyes yubico-authenticator-bin zenity
        ]
        flatpak: {org.remmina.Remmina: d40938f656ca5f3699f63fb3a926d321d24e36c63edb97cca8a3d14108a5c65c}
    }
}

const SHOWN = [org.kde.knetattach org.kde.bluedevilwizard org.kde.plasma.printqueue]
const KDE_ONLY = [systemsettings org.kde.plasma.emojier]
const HIDDEN = [appimagetool byobu]
# caido keeps the 8080 stirling-pdf defaults to
const STIRLING_PORT = 8090

# filezilla nags until a greeting version is stored and rewrites the file on exit, so it is seeded only once
const FILEZILLA_XML = "filezilla/filezilla.xml"

export def filezilla-seed [file: path]: nothing -> nothing {
    if ($file | path exists) { return }
    let installed = ^pacman -Q filezilla | complete
    if $installed.exit_code != 0 { return }
    let version = $installed.stdout | str trim | split row " " | last | str replace --regex '-[0-9.]+$' ''
    mkdir ($file | path dirname)
    [
        '<?xml version="1.0" encoding="UTF-8"?>'
        $'<FileZilla3 version="($version)" platform="*nix">'
        '  <Settings>'
        $'    <Setting name="Greeting version">($version)</Setting>'
        '  </Settings>'
        '</FileZilla3>'
    ] | str join "\n" | $"($in)\n" | save $file
}

def line-drop [pattern: string]: string -> string {
    lines | where $it !~ $pattern | str join "\n" | $"($in)\n"
}

export def link [cfg: record] {
    let apps = xdg data applications
    let run = $nu.home-dir | path join .local bin desktop-run
    let filezilla = xdg config $FILEZILLA_XML
    let values = {HOME: $nu.home-dir, DOTFILES: $env.DOTFILES, STIRLING_PORT: $STIRLING_PORT}
    [(link-commands desktop-run.nu hollywood-run.nu)]
    # Exec needs the absolute path, ~/.local/bin is not on every session's PATH
    | append (glob *.desktop | each {|entry|
        file-render $entry ($apps | path join ($entry | path basename)) $values
    })
    | append ($SHOWN | each {|id| desktop-override $"($id).desktop" { line-drop '^NoDisplay=true$' } })
    | append ($KDE_ONLY | each {|id| desktop-override $"($id).desktop" { line-drop '^OnlyShowIn=KDE;$' } })
    | append ($HIDDEN | each {|id|
        desktop-override $"($id).desktop" { str replace --regex '(?m)^\[Desktop Entry\]$' "[Desktop Entry]\nNoDisplay=true" }
    })
    | append (desktop-override wayvr.desktop {
        desktop-set {Terminal: false} | str replace --regex '(?m)^Exec=wayvr$' $"Exec=($run) --notify -- wayvr"
    })
    | append (if ($filezilla | path exists) { [] } else { [(step filezilla-seed $filezilla)] })
    | append (if (which update-desktop-database | is-not-empty) {
        [(exec desktop-database [update-desktop-database $apps])]
    } else { [] })
}
