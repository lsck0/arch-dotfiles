use module.nu *
use ../../core/wallust/scripts/font.nu [font-load]

export const meta = {packages: {pacman: [bruno-bin bruno-cli]}}

def preferences []: nothing -> record {
    let file = xdg config bruno preferences.json
    let current = try { open $file } catch { {} }
    let installed = package-version bruno-bin
    # declared on every run with the value already there: a key declared only while missing is dropped, and so
    # deleted, by the next run, which sees it present
    let seen = $current.preferences?.onboarding?.lastSeenVersion? | default $installed
    let seen = if $seen == null { [] } else { [(json-set [preferences onboarding lastSeenVersion] $seen)] }
    json-merge $file ([
        (json-set [preferences font codeFont] (font-load).mono)
        # bruno validates telemetry as an object; a bare boolean fails every save
        (json-set [preferences telemetry] {enabled: false})
        (json-set [preferences onboarding hasLaunchedBefore] true)
        (json-set [preferences onboarding hasSeenWelcomeModal] true)
    ] ++ $seen ++ [(json-set [version] ($current.version? | default "1"))])
}

export def link [cfg: record] {
    [
        (preferences)
        # its bundled electron predates 38 and would run on scaled xwayland, unlike every other electron app here
        (desktop-exec bruno.desktop /opt/Bruno/bruno --args [--ozone-platform-hint=auto])
    ]
}

export def theme [cfg: record, wallpaper: string] {
    preferences
}
