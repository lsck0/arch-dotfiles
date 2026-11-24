use module.nu *

export const meta = {packages: {pacman: [polkit]}}

const HELPER = "/usr/local/bin/toggle-root"
const ACTION = "dev.lsck0.toggles.root"
const POLICY = "dev.lsck0.toggles.policy"
const RULES = "49-toggles.rules"
# the helper's stamp of an authenticated lowering, and how long the rule lets the next one pass on it
const APPROVAL_DIR = "/run/toggle-auth"
const APPROVAL_MINUTES = 5
const REAPPLY_UNIT = "toggles-reapply.service"

export def link [cfg: record] {
    [
        (unit-file $"services/($REAPPLY_UNIT)" --values {DOTFILES: $env.DOTFILES} --enable)
    ]
}

export def system [cfg: record] {
    let names = {ACTION: $ACTION, HELPER: $HELPER, APPROVAL_DIR: $APPROVAL_DIR, APPROVAL_MINUTES: $APPROVAL_MINUTES}
    [
        (file-render scripts/toggle-root.nu $HELPER $names --mode 755)
        (file-render $"config/($POLICY)" ("/usr/share/polkit-1/actions" | path join $POLICY) $names)
        (polkit-rules $"config/($RULES)" --values $names)
    ]
}
