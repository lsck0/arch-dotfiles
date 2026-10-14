use module.nu *
export use ../boot/boot.nu [cmdline-set]

export def system [cfg: record] {
    [
        (file-copy 10-storage.conf /etc/systemd/coredump.conf.d/10-storage.conf)
        # sorts before systemd.conf, so its age wins for the coredump directory
        (file-copy coredump-tmpfiles.conf /etc/tmpfiles.d/coredump.conf)
    ] ++ (if $env.FORM_FACTOR? == "wsl" { [] } else {
        # a kernel panic leaves no core: efi_pstore (off in arch's kernel) keeps its last log in nvram, and
        # systemd-pstore moves it to /var/lib/systemd/pstore on the next boot
        [(step cmdline-set efi_pstore.pstore_disable=0) (unit-enable systemd-pstore.service)]
    })
}
