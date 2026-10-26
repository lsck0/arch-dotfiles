use module.nu *

export def link [cfg: record] {
    [
        (if (which tms | is-empty) { [] } else { exec tms-bookmark [tms bookmark $env.PWD] })
        # by repo path: no ~/.local/bin on PATH during the install
        (exec herdr-allow [nu --no-config-file ($env.PWD | path join ../../core/herdr/herdr-open.nu | path expand) allow $env.PWD])
    ]
}
