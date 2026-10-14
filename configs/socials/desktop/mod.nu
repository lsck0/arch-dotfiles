use module.nu *

# this dir is the "desktop" project: tms opens the bookmark as a session and runs .tms-create, herdr-open runs
# .herdr-create; tms adds a bookmark once
export def link [cfg: record] {
    if (which tms | is-empty) { return [] }
    exec tms-bookmark [tms bookmark $env.PWD]
}
