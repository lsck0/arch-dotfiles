use module.nu *

export def link [cfg: record] {
    link-commands sandbox-build.sh confine.sh
}
