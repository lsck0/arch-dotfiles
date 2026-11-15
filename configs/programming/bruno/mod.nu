use module.nu *

export const meta = {packages: {pacman: [bruno-bin bruno-cli]}}

export def link [cfg: record] {
    let file = xdg config bruno preferences.json
    let current = try { open $file } catch { {} }
    let installed = package-version bruno-bin
    # declared on every run with the value already there: a key declared only while missing is dropped, and so
    # deleted, by the next run, which sees it present
    let seen = $current.preferences?.onboarding?.lastSeenVersion? | default $installed
    let seen = if $seen == null { [] } else { [(json-set [preferences onboarding lastSeenVersion] $seen)] }
    json-merge $file ([
        (json-set [preferences font codeFont] "Kode Mono")
        # bruno validates telemetry as an object; a bare boolean fails every save
        (json-set [preferences telemetry] {enabled: false})
        (json-set [preferences onboarding hasLaunchedBefore] true)
        (json-set [preferences onboarding hasSeenWelcomeModal] true)
    ] ++ $seen ++ [(json-set [version] ($current.version? | default "1"))])
}
