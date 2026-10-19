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

# packaged entries hidden from a real app: NoDisplay, or OnlyShowIn=KDE on hyprland (quickshell's hidden-entries.nu)
const SHOWN = [org.kde.knetattach org.kde.bluedevilwizard org.kde.plasma.printqueue]
const KDE_ONLY = [systemsettings org.kde.plasma.emojier]
# appimagetool is a CLI that wants an AppDir, byobu.desktop runs the missing gnome-terminal
const HIDDEN = [appimagetool byobu]

def line-drop [pattern: string]: string -> string {
    lines | where $it !~ $pattern | str join "\n" | $"($in)\n"
}

export def link [cfg: record] {
    let apps = $env.XDG_DATA_HOME? | default ($nu.home-dir | path join .local share) | path join applications
    let run = $nu.home-dir | path join .local bin desktop-run
    [(link-commands desktop-run.nu hollywood-run.nu)]
    # a per-user copy: Exec needs the absolute path, ~/.local/bin is not on every session's PATH
    | append (glob *.desktop | each {|entry|
        file-render $entry ($apps | path join ($entry | path basename)) {HOME: $nu.home-dir, DOTFILES: $env.DOTFILES}
    })
    | append ($SHOWN | each {|id| desktop-override $"($id).desktop" { line-drop '^NoDisplay=true$' } })
    | append ($KDE_ONLY | each {|id| desktop-override $"($id).desktop" { line-drop '^OnlyShowIn=KDE;$' } })
    | append ($HIDDEN | each {|id|
        desktop-override $"($id).desktop" { str replace --regex '(?m)^\[Desktop Entry\]$' "[Desktop Entry]\nNoDisplay=true" }
    })
    | append (desktop-override wayvr.desktop {
        str replace --regex '(?m)^Terminal=true$' 'Terminal=false' | str replace --regex '(?m)^Exec=wayvr$' $"Exec=($run) --notify -- wayvr"
    })
    | append [(exec desktop-database [update-desktop-database $apps])]
}
