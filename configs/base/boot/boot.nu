# only archinstall's layout: uefi, the fat esp at /boot (fmask/dmask 0077, root reads it)

export const ESP = "/boot"
export const EFI_SYSFS = "/sys/firmware/efi"
export const CMDLINE = "/etc/kernel/cmdline"
export const MKINITCPIO = "/etc/mkinitcpio.conf"
export const PRESETS = "/etc/mkinitcpio.d"
const BACKUP = ".arch-dotfiles-backup"
export const UKI_DIR = $"($ESP)/EFI/Linux"
const HOOK_DIRS = [/etc/initcpio/install /usr/lib/initcpio/install]
const SDBOOT_EFI = "/usr/lib/systemd/boot/efi/systemd-bootx64.efi"
export const SDBOOT_ESP_FILES = [$"($ESP)/EFI/systemd/systemd-bootx64.efi" $"($ESP)/EFI/BOOT/BOOTX64.EFI"]
# What the boot chain is built from, the barrier's watch (base/boot/systemd-boot): mkinitcpio's own inputs, the
# initramfs inputs other modules write, and sbctl's keys (signing starts once they exist).
export const BOOT_WATCH = [
    $MKINITCPIO /etc/mkinitcpio.conf.d $PRESETS $CMDLINE /etc/crypttab.initramfs
    /etc/modprobe.d /etc/vconsole.conf
    /etc/bootvine.toml /etc/mkinitcpio-systemd-tool /etc/tinyssh
    /etc/systemd/system/initrd-tinysshd.service.d /etc/systemd/system/initrd-network.service.d
    /etc/systemd/system/initrd-wifi.service
    /var/lib/sbctl
]

export def esp-supported []: nothing -> bool {
    ($EFI_SYSFS | path exists) and (^stat -f -c %T $ESP | str trim) == "msdos"
}

export def backup-once [file: path]: nothing -> nothing {
    if not ($"($file)($BACKUP)" | path exists) { ^install -m644 $file $"($file)($BACKUP)" }
}

export def cmdline-words []: nothing -> list<string> {
    if not ($CMDLINE | path exists) {
        mkdir ($CMDLINE | path dirname)
        open --raw /proc/cmdline | str trim | split row " " | where {|w| not ($w =~ '^(BOOT_IMAGE|initrd)=') }
        | str join " " | save $CMDLINE
    }
    backup-once $CMDLINE
    open --raw $CMDLINE | str trim | split row " " | where $it != ""
}

def cmdline-save [words: list<string>]: nothing -> nothing {
    let text = $words | str join " "
    if $text != (open --raw $CMDLINE | str trim) { $"($text)\n" | save --force $CMDLINE }
}

export def key-of [token: string]: nothing -> string {
    $token | split row "=" | first
}

export def cmdline-set [...tokens: string]: nothing -> nothing {
    if not (esp-supported) { return }
    cmdline-save ($tokens | reduce --fold (cmdline-words) {|t, words|
        $words | where {|w| (key-of $w) != (key-of $t) or $w == $t } | if $t in $in { $in } else { $in | append $t }
    })
}

export def cmdline-unset [...keys: string]: nothing -> nothing {
    if not ($CMDLINE | path exists) { return }
    cmdline-save (cmdline-words | where {|w| (key-of $w) not-in $keys })
}

export def hooks-read []: nothing -> list<string> {
    let line = open --raw $MKINITCPIO | lines | where ($it =~ '^HOOKS=\(') | get --optional 0
    if $line == null { error make {msg: $"no HOOKS=\( line in ($MKINITCPIO)"} }
    $line | parse --regex '^HOOKS=\((?<h>.*)\)' | get 0.h | split row " " | where $it != ""
}

# Rewrites only the live HOOKS= line; the stock file's commented examples stay.
export def hooks-write [hooks: list<string>]: nothing -> nothing {
    if $hooks == (hooks-read) { return }
    backup-once $MKINITCPIO
    open --raw $MKINITCPIO | lines
    | each {|l| if ($l =~ '^HOOKS=\(') { $"HOOKS=\(($hooks | str join ' ')\)" } else { $l } }
    | str join "\n" | $"($in)\n" | save --force $MKINITCPIO
}

# hook placed right before anchor, or right after it with --after.
export def hooks-insert [hooks: list<string>, hook: string, anchor: string, --after]: nothing -> list<string> {
    let at = ($hooks | enumerate | where item == $anchor | get 0.index) + (if $after { 1 } else { 0 })
    ($hooks | first $at) ++ [$hook] ++ ($hooks | skip $at)
}

export def sbctl-ready []: nothing -> bool {
    (which sbctl | is-not-empty) and (^sbctl status | str contains "Owner GUID")
}

export def uki-path [pkgbase: string]: nothing -> path {
    $"($UKI_DIR)/arch-($pkgbase).efi"
}

# Runs sbctl and shows its output only on failure, so already signed files print nothing on every run.
export def --wrapped sbctl-quiet [...args: string]: nothing -> nothing {
    let out = ^sbctl ...$args | complete
    if $out.exit_code != 0 { error make {msg: $"sbctl ($args | str join ' '): ($out.stdout)($out.stderr)"} }
}

def sbctl-sign [...files: path]: nothing -> nothing {
    for f in ($files | where ($it | path type) == file) { sbctl-quiet sign -s $f }
}

# What sbctl verify reports unsigned, but the plain kernels: a type #1 entry on the unverified esp could boot one with
# any cmdline, so they stay unsigned.
export def sbctl-unsigned []: nothing -> list<path> {
    ^sbctl verify | lines | parse --regex '^[^/]*(?<path>/.*) is not signed$' | get path
    | where {|p| not ($p | str starts-with $"($ESP)/vmlinuz-") }
}

# A hook whose package left (sd-bootvine once base/bootvine is off) fails every mkinitcpio, a kernel upgrade's too.
export def hooks-sweep []: nothing -> nothing {
    let hooks = hooks-read
    let kept = $hooks | where {|h| $HOOK_DIRS | any {|d| $d | path join $h | path exists } }
    let dropped = $hooks | where $it not-in $kept
    if ($dropped | is-not-empty) { print $"boot: HOOKS dropped ($dropped | str join ' '), no install script left" }
    hooks-write $kept
}

# The boot barrier, run by the engine once after a system run that changed what BOOT_WATCH covers: one uki rebuild,
# then every boot file signed.
export def boot-commit []: nothing -> nothing {
    if (which mkinitcpio | is-empty) { return }
    hooks-sweep
    ^mkinitcpio -P
    if not (sbctl-ready) { return }
    # -s lists each uki in sbctl's database, so its pacman hook re-signs it after every kernel upgrade
    sbctl-sign ...(glob $"($PRESETS)/*.preset" | each { uki-path ($in | path parse | get stem) })
    sbctl-quiet sign -s -o $"($SDBOOT_EFI).signed" $SDBOOT_EFI
    sbctl-sign ...$SDBOOT_ESP_FILES
    sbctl-quiet sign-all
    let unsigned = sbctl-unsigned | str join " "
    if $unsigned != "" {
        error make {msg: $"boot: unsigned with secure boot keys enrolled, the next boot may fail: ($unsigned)"}
    }
}
