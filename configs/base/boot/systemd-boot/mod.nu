use module.nu *
use ../boot.nu [ESP CMDLINE esp-supported cmdline-set]

export const meta = {
    packages: {native: [amd-ucode intel-ucode linux linux-headers linux-lts linux-lts-headers mkinitcpio]}
    volatile: true
}

const UKI_DIR = "/boot/EFI/Linux"
const PRESETS = "/etc/mkinitcpio.d"

# the ukis this sets up are rebuilt and signed at the system layer's boot barrier (boot.nu boot-commit)
export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" or not (esp-supported) { return [] }
    [
        (step install)
        # a systemd upgrade replaces only the package's loader; this copies sbctl's re-signed .signed onto the esp at
        # the next boot, where a pacman hook running bootctl update would race sbctl's for the last place in hook order
        (unit-enable systemd-boot-update.service)
    ]
}

# each kernel preset builds one uki with its cmdline embedded from CMDLINE alone; bootstrap.sh writes the same preset
export def install []: nothing -> nothing {
    cmdline-set
    let words = open --raw $CMDLINE | str trim | split row " "
    let subvol = (^findmnt -no FSROOT / | str trim) == "/" or ($words | any { $in =~ 'subvol=' })
    if not ($words | any { $in =~ '^root=' }) or not $subvol {
        error make {msg: $"($CMDLINE) lacks root= or the root subvol, not switching to ukis"}
    }
    for preset in (glob $"($PRESETS)/*.preset") {
        let pkgbase = $preset | path parse | get stem
        let want = open --raw $preset | lines
            | where {|l| not ($l =~ '^#?default_(image|uki|cmdline)=') }
            | each {|l| if ($l =~ '^PRESETS=') { "PRESETS=('default')" } else { $l } }
            | append [$'default_uki="($UKI_DIR)/arch-($pkgbase).efi"' $'default_cmdline="($CMDLINE)"']
            | str join "\n" | $"($in)\n"
        if $want == (open --raw $preset) { continue }
        let backup = $"($preset).arch-dotfiles-backup"
        if not ($backup | path exists) { ^install -m644 $preset $backup }
        $want | save --force $preset
        # a kernel installed during the stage chain built a plain image with the stage keyfile in it; nothing boots it
        rm --force $"($ESP)/initramfs-($pkgbase).img" $"($ESP)/initramfs-($pkgbase)-fallback.img"
    }
    if (^bootctl $"--esp-path=($ESP)" is-installed | complete).exit_code != 0 { ^bootctl $"--esp-path=($ESP)" install }
    # cp, not install -m: a chmod on the fmask=0077 fat esp fails
    mkdir $"($ESP)/loader"
    if (open --raw loader.conf) != (try { open --raw $"($ESP)/loader/loader.conf" } catch { "" }) {
        ^cp loader.conf $"($ESP)/loader/loader.conf"
    }
}
