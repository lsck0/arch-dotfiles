use module.nu *

export const meta = {packages: {native: [v4l-utils]}}

export def system [cfg: record] {
    # the wrapper execs /usr/bin/qvidcap: nothing without it (WSL skips native packages)
    if $env.FORM_FACTOR? == "wsl" or not ("/usr/bin/qvidcap" | path exists) { return [] }
    file-copy qvidcap.nu /usr/local/bin/qvidcap --mode 755
}
