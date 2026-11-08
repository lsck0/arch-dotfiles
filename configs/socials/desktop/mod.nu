use module.nu *
use ../../core/herdr/herdr-open.nu [create-allowed]

def tms-bookmarked [dir: path]: nothing -> bool {
    let config = $env.TMS_CONFIG_FILE? | default (xdg config tms config.toml)
    ($config | path exists) and $dir in (try { open $config | get --optional bookmarks | default [] } catch { [] })
}

export def link [cfg: record] {
    [
        (if (which tms | is-empty) or (tms-bookmarked $env.PWD) { [] } else { exec tms-bookmark [tms bookmark $env.PWD] })
        # by repo path: no ~/.local/bin on PATH during the install
        (if (create-allowed ($env.PWD | path join .herdr-create | path expand)) { [] } else {
            exec herdr-allow [nu --no-config-file ($env.PWD | path join ../../core/herdr/herdr-open.nu | path expand) allow $env.PWD]
        })
    ]
}
