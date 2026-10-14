use module.nu *

export const meta = {packages: {native: [v4l-utils]}}

# qvidcap's gl setup fails on native wayland and it exits, under xwayland it runs; /usr/local/bin is ahead on PATH
export def system [cfg: record] {
    file-copy qvidcap.nu /usr/local/bin/qvidcap --mode 755
}
