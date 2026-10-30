use module.nu *
use ../boot/boot.nu [sbctl-quiet sbctl-ready]

# volatile: sign waits for sbctl's own keys, which a later run may create
export const meta = {packages: {native: [fwupd]}, volatile: true}

const EFI = "/usr/lib/fwupd/efi/fwupdx64.efi"

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (file-copy fwupd.conf /etc/fwupd/fwupd.conf --mode 640 --then [systemctl try-restart fwupd.service])
        (unit-enable fwupd-refresh.timer --now)
    ] ++ (if ($EFI | path exists) { [(step sign)] } else { [] })
}

# Signs the fwupd efi binary into sbctl's list, so sbctl's pacman hook re-signs it on every fwupd upgrade.
export def sign []: nothing -> nothing {
    if not (sbctl-ready) { return }
    sbctl-quiet sign -s -o $"($EFI).signed" $EFI
}
