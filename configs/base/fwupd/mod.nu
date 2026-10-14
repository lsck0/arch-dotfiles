use module.nu *

export const meta = {packages: {native: [fwupd]}}

const EFI = "/usr/lib/fwupd/efi/fwupdx64.efi"

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" { return [] }
    [
        (file-copy fwupd.conf /etc/fwupd/fwupd.conf --mode 640 --then [systemctl try-restart fwupd.service])
        # metadata only, updates stay manual: fwupdmgr get-updates, fwupdmgr update
        (unit-enable fwupd-refresh.timer --now)
    ] ++ (if ($EFI | path exists) { [(step sign)] } else { [] })
}

# capsule updates boot fwupdx64.efi; once in sbctl's list its pacman hook re-signs it on every fwupd upgrade
export def sign []: nothing -> nothing {
    if (which sbctl | is-empty) or not (^sbctl status | str contains "Owner GUID") { return }
    ^sbctl sign -s -o $"($EFI).signed" $EFI
}
