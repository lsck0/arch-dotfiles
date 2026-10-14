#!/usr/bin/nu --no-config-file
# after a timeshift restore of @ the esp (not in @) still holds the newer kernels, whose modules the restored
# /usr/lib/modules lacks: put each installed kernel back on the esp and rebuild its uki, as the kernel package's own
# hook does (sbctl's mkinitcpio post hook signs it), then reboot once when the running kernel was one of them

def main []: nothing -> nothing {
    let stale = glob /usr/lib/modules/*/pkgbase | each {|f|
        let dir = $f | path dirname
        {dir: $dir, kver: ($dir | path basename), pkgbase: (open --raw $f | str trim)}
    } | where {|k|
        # by the version in the image header, so a signed copy still matches
        ($"($k.dir)/vmlinuz" | path exists)
        and not ((^file -bL $"/boot/vmlinuz-($k.pkgbase)" | complete).stdout | str contains $", version ($k.kver) ")
    }
    for k in $stale {
        let image = $"/boot/vmlinuz-($k.pkgbase)"
        print --stderr $"kernel-resync: ($image) is not ($k.kver), restoring it from the installed ($k.pkgbase)"
        ^install -Dm644 $"($k.dir)/vmlinuz" $image
        ^mkinitcpio -p $k.pkgbase
    }
    # the next boot finds the kernel in step, so this reboots at most once; from the iso (ROLLBACK.md) the chroot ends
    let running = ^uname -r | str trim
    let chroot = (^systemd-detect-virt -q --chroot | complete).exit_code == 0
    if ($stale | is-not-empty) and not ($"/usr/lib/modules/($running)" | path exists) and not $chroot {
        print --stderr $"kernel-resync: running ($running) without its modules, rebooting into the restored kernel"
        ^systemctl reboot
    }
}
