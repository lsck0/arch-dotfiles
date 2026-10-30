# only archinstall's layout: uefi, the fat esp at /boot (fmask/dmask 0077, root reads it)

use state.nu [SYSTEM_STATE]

export const ESP = "/boot"
export const CMDLINE = "/etc/kernel/cmdline"
export const MKINITCPIO = "/etc/mkinitcpio.conf"
const BACKUP = ".arch-dotfiles-backup"
export const UKI_DIR = "/boot/EFI/Linux"
const SDBOOT_EFI = "/usr/lib/systemd/boot/efi/systemd-bootx64.efi"
export const SDBOOT_ESP_FILES = ["/boot/EFI/systemd/systemd-bootx64.efi" "/boot/EFI/BOOT/BOOTX64.EFI"]
const BOOT_INPUTS = [
    /etc/mkinitcpio.conf /etc/mkinitcpio.conf.d /etc/mkinitcpio.d /etc/kernel/cmdline /etc/crypttab.initramfs
    /etc/modprobe.d /etc/vconsole.conf
    /etc/plymouth /usr/share/plymouth/themes /etc/mkinitcpio-systemd-tool /etc/tinyssh
    /etc/systemd/system/initrd-tinysshd.service.d /etc/systemd/system/initrd-network.service.d
    /etc/systemd/system/initrd-wifi.service
]

export def esp-supported []: nothing -> bool {
    ("/sys/firmware/efi" | path exists) and (^stat -f -c %T $ESP | str trim) == "msdos"
}

def backup-once [file: path]: nothing -> nothing {
    if not ($"($file)($BACKUP)" | path exists) { ^install -m644 $file $"($file)($BACKUP)" }
}

def cmdline-words []: nothing -> list<string> {
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

def key-of [token: string]: nothing -> string {
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

export def hooks-insert [hooks: list<string>, hook: string, at: int]: nothing -> list<string> {
    ($hooks | first $at) ++ [$hook] ++ ($hooks | skip $at)
}

def boot-inputs-hash []: nothing -> string {
    $BOOT_INPUTS | where ($it | path exists)
    | each {|p| if ($p | path type) == dir { glob $"($p)/**/*" --no-dir --no-symlink | sort } else { [$p] } } | flatten
    | each {|f| $"(ls --long $f | get 0.mode) ($f) (open --raw $f | hash sha256)" } | str join "\n" | hash sha256
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

# The boot barrier, last in a system run: one uki rebuild for the whole run, then every boot file signed.
export def boot-commit []: nothing -> nothing {
    if (which mkinitcpio | is-empty) { return }
    let stamp = $SYSTEM_STATE | path join boot-inputs
    let inputs = boot-inputs-hash
    if $inputs != (try { open --raw $stamp } catch { "" }) {
        ^mkinitcpio -P
        mkdir $SYSTEM_STATE
        $inputs | save --force $stamp
    }
    if not (sbctl-ready) { return }
    # -s lists each uki in sbctl's database, so its pacman hook re-signs it after every kernel upgrade
    sbctl-sign ...(glob /etc/mkinitcpio.d/*.preset | each { uki-path ($in | path parse | get stem) })
    sbctl-quiet sign -s -o $"($SDBOOT_EFI).signed" $SDBOOT_EFI
    sbctl-sign ...$SDBOOT_ESP_FILES
    sbctl-quiet sign-all
    # plain kernels stay unsigned: a type #1 entry on the unverified esp could boot one with any cmdline
    let unsigned = ^sbctl verify | lines
        | where ($it =~ 'is not signed') and not ($it | str contains $"($ESP)/vmlinuz-") | str join " "
    if $unsigned != "" {
        error make {msg: $"boot: unsigned with secure boot keys enrolled, the next boot may fail: ($unsigned)"}
    }
}
