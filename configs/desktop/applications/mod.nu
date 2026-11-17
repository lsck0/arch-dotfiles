use module.nu *

export const meta = {
    reads: [desktop/hyprland]
    packages: {
        pacman: [
            ani-cli-git bleachbit bluetui chawan filezilla font-manager gearlever geogebra-6-bin gnome-calculator
            gnome-calendar gnome-maps gnome-text-editor hollywood josm kleopatra linecast localsend
            logseq-desktop-bin lynx metadata-cleaner minder mov-cli mpg123 nemo gvfs okular onlyoffice-bin piper
            proton-authenticator-bin proton-pass-bin proton-vpn-qt-app snapshot sowon-git stirling-pdf-bin tlpui
            torbrowser-launcher waypipe wev wine-gecko wine-mono wine-staging xorg-xeyes yubico-authenticator-bin zenity
        ]
        flatpak: {org.remmina.Remmina: d40938f656ca5f3699f63fb3a926d321d24e36c63edb97cca8a3d14108a5c65c} # built 2026-02-23
    }
}

const SHOWN = [org.kde.knetattach org.kde.bluedevilwizard org.kde.plasma.printqueue]
const KDE_ONLY = [systemsettings org.kde.plasma.emojier]
const HIDDEN = [appimagetool byobu]
# caido keeps the 8080 stirling-pdf defaults to
const STIRLING_PORT = 8090
const APPS = "apps.nuon"

# filezilla nags until a greeting version is stored and rewrites the file on exit, so it is seeded only once
const FILEZILLA_XML = "filezilla/filezilla.xml"

export def filezilla-seed [file: path]: nothing -> nothing {
    if ($file | path exists) { return }
    let version = package-version filezilla
    if $version == null { return }
    mkdir ($file | path dirname)
    [
        '<?xml version="1.0" encoding="UTF-8"?>'
        $'<FileZilla3 version="($version)" platform="*nix">'
        '  <Settings>'
        $'    <Setting name="Greeting version">($version)</Setting>'
        '  </Settings>'
        '</FileZilla3>'
    ] | to text | save $file
}

# onlyoffice keeps its interface scale as flat <key>value</key> pairs in this file, rewritten by its settings dialog
const ONLYOFFICE_SETTINGS = "onlyoffice/desktopeditors/data/settings.xml"

def onlyoffice-scale-values [scale: int]: nothing -> record {
    {force-scale: ($scale | into string), system-scale: "0"}
}

export def onlyoffice-scale [file: path, scale: string]: nothing -> nothing {
    let text = if ($file | path exists) { open --raw $file } else { "<Settings></Settings>" }
    let values = onlyoffice-scale-values ($scale | into int)
    let out = $values | transpose key value | reduce --fold $text {|pair, acc|
        let tag = $"<($pair.key)>($pair.value)</($pair.key)>"
        if ($acc | str contains $"<($pair.key)>") {
            $acc | str replace --regex $"<($pair.key)>[^<]*</($pair.key)>" $tag
        } else {
            $acc | str replace "</Settings>" $"($tag)</Settings>"
        }
    }
    mkdir ($file | path dirname)
    $out | save --force $file
}

def onlyoffice-scale-step [scale: int]: nothing -> record {
    let file = xdg data $ONLYOFFICE_SETTINGS
    let text = if ($file | path exists) { open --raw $file } else { "" }
    let done = onlyoffice-scale-values $scale | transpose key value
        | all {|pair| $text | str contains $"<($pair.key)>($pair.value)</($pair.key)>" }
    step onlyoffice-scale $file ($scale | into string) --done=$done
}

# the default prefix behind winecfg and the wine launchers; its win32 ui draws 1:1 on xwayland's unscaled surface
const WINE_REGISTRY = ".wine/user.reg"
const WINE_DESKTOP_KEY = 'HKCU\Control Panel\Desktop'
const WINE_DESKTOP_SECTION = '[Control Panel\\Desktop] '
const WINE_DPI_BASE = 96

export def wine-dpi [dpi: string]: nothing -> nothing {
    with-env {WINEDEBUG: "-all"} { ^wine reg add $WINE_DESKTOP_KEY /v LogPixels /t REG_DWORD /d $dpi /f }
}

# wine creates the prefix on its first run; until then there is nothing to set
def wine-dpi-step [scale: int]: nothing -> oneof<record, nothing> {
    let registry = $nu.home-dir | path join $WINE_REGISTRY
    if not ($registry | path exists) { return null }
    let dpi = $WINE_DPI_BASE * $scale
    let dword = $dpi | format number | get lowerhex | str replace "0x" "" | fill --alignment right --character "0" --width 8
    let done = open --raw $registry | split row "\n\n" | where ($it | str starts-with $WINE_DESKTOP_SECTION)
        | any { str contains $'"LogPixels"=dword:($dword)' }
    step wine-dpi ($dpi | into string) --done=$done
}

def line-drop [pattern: string]: string -> string {
    lines | where $it !~ $pattern | to text
}

# An apps.nuon row as a launcher entry with each @key@ replaced by its value; a ConsoleOnly app runs in a terminal.
def app-entry [app: record, values: record]: nothing -> string {
    let text = [
        "[Desktop Entry]"
        "Type=Application"
        $"Name=($app.name? | default $app.id)"
        $"Comment=($app.comment)"
        $"TryExec=($app.tryexec? | default $app.id)"
        $"Exec=($app.exec? | default $app.id)"
        $"Icon=($app.icon)"
        $"Terminal=("ConsoleOnly" in $app.categories)"
        $"Categories=($app.categories | str join ';');"
    ] | to text
    $values | transpose key value | reduce --fold $text {|pair, acc| $acc | str replace --all $"@($pair.key)@" ($pair.value | into string) }
}

export def link [cfg: record] {
    let apps = xdg data applications
    # Exec needs the absolute path, ~/.local/bin is not on every session's PATH
    let bin = $nu.home-dir | path join .local bin
    let filezilla = xdg config $FILEZILLA_XML
    let values = {HOME: $nu.home-dir, BIN: $bin, DOTFILES: $env.DOTFILES, STIRLING_PORT: $STIRLING_PORT}
    [
        (link-commands desktop-run.nu hollywood-run.nu)
        # tk takes its scale from the x screen's 96 dpi and ignores GDK_SCALE: these wrappers scale it at start
        (if ("/usr/bin/idle" | path exists) { link-commands idle.py })
        (if ("/usr/bin/gitk" | path exists) { link-commands gitk.tcl })
        (open $APPS | each {|app| file-text ($apps | path join $"($app.id).desktop") (app-entry $app $values) })
        ($SHOWN | each {|id| desktop-override $"($id).desktop" { desktop-set {NoDisplay: false} } })
        ($KDE_ONLY | each {|id| desktop-override $"($id).desktop" { line-drop '^OnlyShowIn=KDE;$' } })
        ($HIDDEN | each {|id| desktop-override $"($id).desktop" { desktop-set {NoDisplay: true} } })
        (desktop-override wayvr.desktop {
            desktop-set {Terminal: false} | str replace --regex '(?m)^Exec=wayvr$' $"Exec=($bin)/desktop-run --notify -- wayvr"
        })
        # its import's file input sends a *.json filter with an empty name, which the portal refuses ("invalid filter: name
        # is empty") and the button does nothing: gtk's own chooser takes it
        (desktop-override "Proton Authenticator.desktop" {
            str replace --regex '(?m)^Exec=env ' 'Exec=env GTK_USE_PORTAL=0 '
        })
        (step filezilla-seed $filezilla --creates $filezilla)
        # its own title bar draws a frame and shadow inside the tile
        (ini-merge (xdg config onlyoffice DesktopEditors.conf) {General: {titlebar: "system"}})
        # qt5 under xwayland sees scale 1 (force_zero_scaling) and ignores GDK_SCALE, so its ui scale is forced to the
        # xwayland one
        (onlyoffice-scale-step (xwayland-scale-for $cfg))
        (wine-dpi-step (xwayland-scale-for $cfg))
        # wine's menu builder registers every prefix's file handlers as this user's defaults (.crt, .reg, .vbs, .chm went
        # to notepad in a deleted scratch prefix); prefixes here are throwaway or launched by their own script
        (file-text (xdg config environment.d wine.conf) "WINEDLLOVERRIDES=winemenubuilder.exe=d\n")
    ]
}
