use module.nu *

export def link [cfg: record] {
    link-commands scripts/sandbox-build.sh scripts/confine.sh
}
