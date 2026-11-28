use module.nu *

export const meta = {reads: [desktop/hyprland], packages: {pacman: [jdownloader2]}}

const SETTINGS = {
    # the package is a bootstrap: core and hoster plugins come only from JD's updater, so it checks and offers
    "org.jdownloader.updatev2.UpdateSettings.json": {autoupdatecheckenabled: true, installupdatesonexitenabled: false}
    "org.jdownloader.jdserv.stats.StatsManagerConfigV2.json": {enabled: false}
    "org.jdownloader.settings.GraphicalUserInterfaceSettings.json": {bannerenabled: false, specialdealsenabled: false}
    # awt SystemTray needs an xembed tray hyprland lacks; freshinstall false keeps JD from re-applying defaults
    "org.jdownloader.gui.jdtrayicon.TrayExtension.json": {enabled: false, freshinstall: false}
}

export def link [cfg: record] {
    let java = {JDK_JAVA_OPTIONS: $"-Dsun.java2d.uiScale=(xwayland-scale-for $cfg)"}
    let dir = $nu.home-dir | path join .jd cfg
    [
        ([jdownloader.desktop jd-containers.desktop] | each { desktop-exec $in JDownloader --env-vars $java })
        ($SETTINGS | items {|file, keys| json-merge ($dir | path join $file) $keys })
    ]
}
