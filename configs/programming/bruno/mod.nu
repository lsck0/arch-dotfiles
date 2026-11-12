use module.nu *

export const meta = {packages: {pacman: [bruno-bin bruno-cli]}}

export def link [cfg: record] {
    let file = xdg config bruno preferences.json
    let current = try { open $file } catch { {} }
    let installed = ^pacman -Q bruno-bin | complete | get stdout | parse --regex ' (?<v>\d+\.\d+\.\d+)' | get --optional 0.v
    let seen = if $installed == null or $current.preferences?.onboarding?.lastSeenVersion? != null { [] } else {
        [(json-set [preferences onboarding lastSeenVersion] $installed)]
    }
    json-merge $file ([
        (json-set [preferences font codeFont] "Kode Mono")
        # bruno validates telemetry as an object; a bare boolean fails every save
        (json-set [preferences telemetry] {enabled: false})
        (json-set [preferences onboarding hasLaunchedBefore] true)
        (json-set [preferences onboarding hasSeenWelcomeModal] true)
    ] ++ $seen ++ (if $current.version? == null { [(json-set [version] "1")] } else { [] }))
}
