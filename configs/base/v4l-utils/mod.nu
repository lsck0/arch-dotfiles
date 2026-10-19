use module.nu *

export const meta = {packages: {native: [v4l-utils]}}

export def system [cfg: record] {
    file-copy qvidcap.nu /usr/local/bin/qvidcap --mode 755
}
