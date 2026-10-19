use module.nu *

export def link [cfg: record] {
    link-commands sandbox-build.nu confine.nu
}
