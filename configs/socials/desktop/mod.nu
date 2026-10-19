use module.nu *

export def link [cfg: record] {
    if (which tms | is-empty) { return [] }
    exec tms-bookmark [tms bookmark $env.PWD]
}
