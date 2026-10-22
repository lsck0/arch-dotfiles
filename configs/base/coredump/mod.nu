use module.nu *
export use ../boot/boot.nu [cmdline-set]

export const options = {
    max_use: {
        type: string
        default: "256M"
        doc: "Total disk space systemd-coredump may keep across every stored core, systemd.coredump(5) size syntax"
        label: "Max total coredump storage"
        scope: machine
    }
    process_size_max: {
        type: string
        default: "1G"
        doc: "Largest process core systemd-coredump will process at all, above it the core is skipped entirely"
        label: "Max process size to dump"
        scope: machine
    }
    external_size_max: {
        type: string
        default: "1G"
        doc: "Largest core systemd-coredump will write to storage, independent of the process size limit"
        label: "Max stored core size"
        scope: machine
    }
}

export def system [cfg: record] {
    [
        (file-render 10-storage.conf /etc/systemd/coredump.conf.d/10-storage.conf {
            MAX_USE: $cfg.max_use, PROCESS_SIZE_MAX: $cfg.process_size_max, EXTERNAL_SIZE_MAX: $cfg.external_size_max
        })
        # sorts before systemd.conf, so its age wins
        (file-copy coredump-tmpfiles.conf /etc/tmpfiles.d/coredump.conf)
    ] ++ (if $env.FORM_FACTOR? == "wsl" { [] } else {
        [(step cmdline-set efi_pstore.pstore_disable=0) (unit-enable systemd-pstore.service)]
    })
}
