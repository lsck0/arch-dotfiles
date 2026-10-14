use module.nu *

export const meta = {packages: {pacman: [bruno-bin bruno-cli]}}

const PREFERENCES = ".config/bruno/preferences.json"

# bruno validates telemetry as an object; a bare boolean fails every save. the theme is window state, not a preference
export def link [cfg: record] {
    let file = $nu.home-dir | path join $PREFERENCES
    let current = try { open $file } catch { {} }
    let telemetry = if ($current.preferences?.telemetry? | describe) =~ "^record" {
        json-set [preferences telemetry enabled] false
    } else {
        json-set [preferences telemetry] {enabled: false}
    }
    json-merge $file ([
        (json-delete [preferences theme])
        (json-set [preferences font codeFont] "Kode Mono")
        $telemetry
    ] ++ (if $current.version? == null { [(json-set [version] "1")] } else { [] }))
}
