use module.nu *

export const meta = {packages: {native: [v4l-utils]}}

export def system [cfg: record] {
    # a PATH wrapper (qvidcap.nu says why), not desktop-override: qvidcap is run from the CLI too
    if $env.FORM_FACTOR? == "wsl" or not ("/usr/bin/qvidcap" | path exists) { return [] }
    file-copy qvidcap.nu /usr/local/bin/qvidcap --mode 755
}
