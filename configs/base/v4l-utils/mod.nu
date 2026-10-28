use module.nu *

export const meta = {packages: {native: [v4l-utils]}}

export def system [cfg: record] {
    # a PATH wrapper, not desktop-override: qvidcap is run from the CLI too, and both paths need
    # QT_QPA_PLATFORM=xcb (its gl setup fails on native wayland). Nothing to do without it (WSL skips native packages).
    if $env.FORM_FACTOR? == "wsl" or not ("/usr/bin/qvidcap" | path exists) { return [] }
    file-copy qvidcap.nu /usr/local/bin/qvidcap --mode 755
}
