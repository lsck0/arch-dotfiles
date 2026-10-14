use module.nu *

# the "desktop" project: tms runs .tms-create, herdr-open runs .herdr-create
export def link [cfg: record] {
    if (which tms | is-empty) { return [] }
    exec tms-bookmark [tms bookmark $env.PWD]
}
