use module.nu *

export const meta = {packages: {pacman: [bruno-bin bruno-cli]}}

const PREFERENCES = ".config/bruno/preferences.json"

export def link [cfg: record] {
    let file = $nu.home-dir | path join $PREFERENCES
    let current = try { open $file } catch { {} }
    let installed = ^pacman -Q bruno-bin | complete | get stdout | parse --regex ' (?<v>\d+\.\d+\.\d+)' | get --optional 0.v
    let seen = if $installed == null or $current.preferences?.onboarding?.lastSeenVersion? != null { [] } else {
        [(json-set [preferences onboarding lastSeenVersion] $installed)]
    }
    json-merge $file ([
        (json-set [preferences font codeFont] "Kode Mono")
        (json-set [preferences telemetry enabled] false)
        (json-set [preferences onboarding hasLaunchedBefore] true)
        (json-set [preferences onboarding hasSeenWelcomeModal] true)
    ] ++ $seen ++ (if $current.version? == null { [(json-set [version] "1")] } else { [] }))
}
