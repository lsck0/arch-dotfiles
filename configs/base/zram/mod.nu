use module.nu *

export const meta = {packages: {native: [zram-generator]}}

export const options = {
    compression_algorithm: {
        type: string
        default: "zstd"
        doc: "Compression used for the zram swap device, zram-generator.conf(5) compression-algorithm (a weaker CPU may prefer lz4)"
        label: "Zram compression algorithm"
    }
    swappiness: {
        type: int
        default: 150
        doc: "How aggressively the kernel swaps to zram versus reclaiming page cache, sysctl(8) vm.swappiness (a zram swap favors higher than disk swap's usual 60)"
        min: 0
        max: 200
    }
}

const MGLRU = "/sys/kernel/mm/lru_gen/min_ttl_ms"
const MGLRU_TMPFILES = "/etc/tmpfiles.d/mglru.conf"

export def system [cfg: record] {
    [
        (if ($MGLRU | path exists) {
            file-copy mglru-tmpfiles.conf $MGLRU_TMPFILES --then [systemd-tmpfiles --create $MGLRU_TMPFILES]
        } else { [] })
        (if ("/usr/lib/systemd/system-generators/zram-generator" | path exists) {
            [
                (file-render sysctl-zram.conf /etc/sysctl.d/99-zram.conf {SWAPPINESS: $cfg.swappiness}
                    --then [/usr/lib/systemd/systemd-sysctl /etc/sysctl.d/99-zram.conf])
                (file-render zram-generator.conf /etc/systemd/zram-generator.conf {COMPRESSION_ALGORITHM: $cfg.compression_algorithm}
                    --then [systemctl daemon-reload])
            ]
        } else { [] })
    ] | decls-flatten
}
