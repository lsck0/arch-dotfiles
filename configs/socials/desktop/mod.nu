use module.nu *

export def link [cfg: record] {
    [
        (if (which tms | is-empty) { [] } else { exec tms-bookmark [tms bookmark $env.PWD] })
        # this repo's own scaffold, so herdr-open may run it; any other .herdr-create needs a manual allow
        (if (which herdr-open | is-empty) { [] } else { exec herdr-allow [herdr-open allow $env.PWD] })
    ]
}
