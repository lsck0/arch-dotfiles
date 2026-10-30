# failure-notify's doctor check no longer saves its findings for the bar's removed doctor indicator; the last
# copy it wrote goes.

use module.nu [xdg]

export def up []: nothing -> nothing {
    rm --force (xdg state doctor findings)
}
