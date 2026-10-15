use module.nu *

export const meta = {packages: {native: [zram-generator]}}

const MGLRU = "/sys/kernel/mm/lru_gen/min_ttl_ms"
const MGLRU_TMPFILES = "/etc/tmpfiles.d/mglru.conf"

# with or without zram: a build cannot evict the desktop's hot pages before oomd's 20s window sees pressure
export def system [cfg: record] {
    [
        (if ($MGLRU | path exists) {
            file-copy mglru-tmpfiles.conf $MGLRU_TMPFILES --then [systemd-tmpfiles --create $MGLRU_TMPFILES]
        } else { [] })
        # swappiness 150 only pays off with zram; without the generator a disk swap would get it
        (if ("/usr/lib/systemd/system-generators/zram-generator" | path exists) {
            [
                (file-copy sysctl-zram.conf /etc/sysctl.d/99-zram.conf --then [/usr/lib/systemd/systemd-sysctl /etc/sysctl.d/99-zram.conf])
                (file-copy zram-generator.conf /etc/systemd/zram-generator.conf --then [systemctl daemon-reload])
            ]
        } else { [] })
    ] | decls-flatten
}
