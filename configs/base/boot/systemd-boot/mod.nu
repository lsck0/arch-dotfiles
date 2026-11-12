use module.nu *
use ../boot.nu [ESP CMDLINE BOOT_WATCH PRESETS backup-once cmdline-words esp-supported hooks-sweep uki-path]
export use ../boot.nu [boot-commit]

# its barrier rebuilds and signs the boot chain once after a system run that changed any of BOOT_WATCH
export const meta = {
    packages: {native: [amd-ucode intel-ucode kernel-modules-hook linux linux-headers linux-lts linux-lts-headers mkinitcpio]}
    volatile: true
    barrier: {run: boot-commit, watch: $BOOT_WATCH}
}

export def system [cfg: record] {
    if $env.FORM_FACTOR? == "wsl" or not (esp-supported) { return [] }
    [
        (step install)
        # not a pacman hook: bootctl update would race sbctl's re-sign hook for the last place in hook order
        (unit-enable systemd-boot-update.service)
        # kernel-modules-hook keeps the running kernel's modules through a kernel upgrade or downgrade; this drops
        # them after the next boot
        (unit-enable linux-modules-cleanup.service)
    ]
}

export def install []: nothing -> nothing {
    # every run, not only the barrier's: a pacman kernel upgrade rebuilds with the HOOKS line as it stands
    hooks-sweep
    let words = cmdline-words
    let subvol = (^findmnt -no FSROOT / | str trim) == "/" or ($words | any { $in =~ 'subvol=' })
    if not ($words | any { $in =~ '^root=' }) or not $subvol {
        error make {msg: $"($CMDLINE) lacks root= or the root subvol, not switching to ukis"}
    }
    for preset in (glob $"($PRESETS)/*.preset") {
        let pkgbase = $preset | path parse | get stem
        let want = open --raw $preset | lines
            | where {|l| not ($l =~ '^#?default_(image|uki|cmdline)=') }
            | each {|l| if ($l =~ '^PRESETS=') { "PRESETS=('default')" } else { $l } }
            | append [$'default_uki="(uki-path $pkgbase)"' $'default_cmdline="($CMDLINE)"']
            | str join "\n" | $"($in)\n"
        if $want == (open --raw $preset) { continue }
        backup-once $preset
        $want | save --force $preset
        # a kernel installed during the stage chain built a plain image with the stage keyfile in it
        rm --force $"($ESP)/initramfs-($pkgbase).img" $"($ESP)/initramfs-($pkgbase)-fallback.img"
    }
    if (^bootctl $"--esp-path=($ESP)" is-installed | complete).exit_code != 0 { ^bootctl $"--esp-path=($ESP)" install }
    # cp, not install -m: a chmod on the fmask=0077 fat esp fails
    mkdir $"($ESP)/loader"
    if (open --raw loader.conf) != (try { open --raw $"($ESP)/loader/loader.conf" } catch { "" }) {
        ^cp loader.conf $"($ESP)/loader/loader.conf"
    }
}
