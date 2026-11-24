use module.nu *

export const meta = {packages: {native: [zram-generator]}}

export const options = {
    size: {
        type: string
        default: "ram"
        doc: "Size of the zram swap device, zram-generator.conf(5) zram-size expression over ram (MiB)"
        label: "Zram size"
        apply: reboot
    }
    compression_algorithm: {
        type: string
        default: "zstd"
        doc: "Compression used for the zram swap device, zram-generator.conf(5) compression-algorithm (a weaker CPU may prefer lz4)"
        label: "Zram compression algorithm"
        choices: [zstd lz4 lzo-rle lzo]
        apply: reboot
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
const ZRAM_GENERATOR = "/usr/lib/systemd/system-generators/zram-generator"
const SYSCTL = "/etc/sysctl.d/99-zram.conf"

export def system [cfg: record] {
    [
        (if ($MGLRU | path exists) {
            file-copy config/mglru-tmpfiles.conf $MGLRU_TMPFILES --then [systemd-tmpfiles --create $MGLRU_TMPFILES]
        })
        (if ($ZRAM_GENERATOR | path exists) {
            [
                (file-render config/sysctl-zram.conf $SYSCTL {SWAPPINESS: $cfg.swappiness} --then [/usr/lib/systemd/systemd-sysctl $SYSCTL])
                (file-render config/zram-generator.conf /etc/systemd/zram-generator.conf
                    {SIZE: $cfg.size, COMPRESSION_ALGORITHM: $cfg.compression_algorithm} --then [systemctl daemon-reload])
            ]
        })
    ]
}
