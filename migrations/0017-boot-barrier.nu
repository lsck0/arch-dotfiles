# The boot chain's rebuild became base/boot/systemd-boot's barrier, recorded with the module; boot-commit's own
# input stamp is gone.

use module.nu [SYSTEM_STATE]

export const layer = "system"

export def up []: nothing -> nothing {
    rm --force ($SYSTEM_STATE | path join boot-inputs)
}
