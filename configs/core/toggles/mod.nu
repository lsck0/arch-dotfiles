use module.nu *

export const meta = {packages: {pacman: [polkit]}}

const HELPER = "/usr/local/bin/toggle-root"
const ACTION = "dev.lsck0.toggles.root"
const POLICY = "dev.lsck0.toggles.policy"
const RULES = "49-toggles.rules"

export def system [cfg: record] {
    let names = {ACTION: $ACTION, HELPER: $HELPER}
    [
        (file-copy toggle-root.nu $HELPER --mode 755)
        (file-render $POLICY ("/usr/share/polkit-1/actions" | path join $POLICY) $names)
        (polkit-rules $RULES --values $names)
    ]
}
