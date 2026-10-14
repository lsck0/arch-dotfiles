use module.nu *

export const meta = {deps: [desktop/hyprland], packages: {pacman: [jdownloader2]}}

# JD rewrites its cfg files itself, so only these keys are merged in
const SETTINGS = {
    "org.jdownloader.updatev2.UpdateSettings.json": {autoupdatecheckenabled: false, installupdatesonexitenabled: false}
    "org.jdownloader.jdserv.stats.StatsManagerConfigV2.json": {enabled: false}
    "org.jdownloader.settings.GraphicalUserInterfaceSettings.json": {bannerenabled: false, specialdealsenabled: false}
    # awt SystemTray needs an xembed tray hyprland lacks; freshinstall false keeps JD from re-applying defaults
    "org.jdownloader.gui.jdtrayicon.TrayExtension.json": {enabled: false, freshinstall: false}
}

export def link [cfg: record] {
    let scale = $cfg.deps?."desktop/hyprland"?.xwayland_scale? | default (display-xwayland-scale ($env.FORM_FACTOR? | default ""))
    let java = { str replace --all --regex '(?m)^Exec=' $"Exec=env JDK_JAVA_OPTIONS=-Dsun.java2d.uiScale=($scale) " }
    # user scope (~/.jd, per /opt/JDownloaderScripts/functions.sh) unless the user is in the jdownloader group
    let dir = $nu.home-dir | path join .jd cfg
    [
        (desktop-override jdownloader.desktop $java)
        (desktop-override jd-containers.desktop $java)
        ($SETTINGS | items {|file, keys| json-merge ($dir | path join $file) ($keys | items {|k, v| json-set [$k] $v }) })
    ]
}
