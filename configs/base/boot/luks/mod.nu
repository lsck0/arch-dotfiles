use module.nu *
use ../boot.nu [cmdline-set hooks-read hooks-write hooks-insert]

export const meta = {packages: {native: [cryptsetup]}, volatile: true}

const MARKER = "# MARKER:arch-dotfiles/boot/luks"
const CRYPTTAB = "/etc/crypttab"
const ENTRY_OPTIONS = "luks,nofail,discard,perf-no-read-workqueue,perf-no-write-workqueue"
# PCR 15 before any volume key is measured into it
const PCR15_INITIAL = "0000000000000000000000000000000000000000000000000000000000000000"

def luks-parts []: nothing -> table {
    ^lsblk -J -l -o NAME,UUID,FSTYPE,TYPE | from json | get blockdevices | where fstype == crypto_LUKS and type == part
}

export def system [cfg: record] {
    if (luks-parts | is-empty) { return [] }
    step configure
}

def root-backing []: nothing -> any {
    let src = ^findmnt -n -o SOURCE / | str trim | split row "[" | first
    if not ($src | str starts-with /dev/mapper/) { return null }
    ^lsblk -J -lso NAME,TYPE $src | from json | get blockdevices | where type == part | get --optional 0.name
}

def crypttab-write [root: any]: nothing -> nothing {
    if ($CRYPTTAB | path exists) {
        if not (open --raw $CRYPTTAB | str contains $MARKER) {
            ^install -m644 $CRYPTTAB $"($CRYPTTAB).arch-dotfiles-backup"
        }
    } else {
        ^install -Dm644 crypttab $CRYPTTAB
    }
    let kept = open --raw $CRYPTTAB | lines | take until {|l| $l == $MARKER }
    let named = $kept | each { split row --regex '\s+' | first }
    let entries = luks-parts | where name != $root and $"luks-($it.uuid)" not-in $named | where {|p|
        let disk = ^lsblk -dno PKNAME $"/dev/($p.name)" | str trim
        (^lsblk -dno RM,HOTPLUG $"/dev/($disk)" | str replace --all " " "" | str trim) == "00"
    } | each {|p| $"luks-($p.uuid)\tUUID=($p.uuid)\tnone\t($ENTRY_OPTIONS)" }
    $kept | append $MARKER | append $entries | str join "\n" | $"($in)\n" | save --force $CRYPTTAB
    print $"luks: crypttab configured, ($entries | length) non-root LUKS volume\(s\)"
}

# Places sd-encrypt (encrypt without systemd); only systemd-cryptsetup reads rd.luks.options=fido2-device=auto.
def hook-place []: nothing -> nothing {
    let hooks = hooks-read
    let hook = if "systemd" in $hooks { "sd-encrypt" } else { "encrypt" }
    let present = $hooks | where $it in [sd-encrypt encrypt]
    if "sd-encrypt" not-in $present and (($present | is-not-empty) or $hook == "encrypt") {
        print ("note: luks: busybox encrypt ignores rd.luks.options, the yubikey unlock needs the systemd and "
            + "sd-encrypt hooks")
    }
    if ($present | is-not-empty) { return }
    for need in [filesystems block keyboard] {
        if $need not-in $hooks { error make {msg: $"luks: HOOKS has no `($need)` hook, refusing to place `($hook)`"} }
    }
    hooks-write (hooks-insert $hooks $hook ($hooks | enumerate | where item == filesystems | get 0.index))
}

# Enrolls the root's tpm seal bound to PCR 15's initial zero, so it never opens after another volume was unlocked.
def root-unlock [part: string]: nothing -> nothing {
    let header = ^cryptsetup luksDump $"/dev/($part)"
    # with tpm2-measure-pcr, fido2-device=auto and no enrolled token fail the unlock without asking the passphrase
    let fido = $header | str contains systemd-fido2
    if not $fido {
        print ("note: luks: no yubikey enrolled, once the stage chain is done: "
            + $"sudo systemd-cryptenroll --fido2-device=auto /dev/($part), then rerun dot apply")
    }
    cmdline-set $"rd.luks.options=tpm2-device=auto(if $fido { ',fido2-device=auto' } else { '' }),tpm2-measure-pcr=yes"
    # never TPM-only: any signed uki would unseal it unattended
    let enroll = $"systemd-cryptenroll --tpm2-device=auto --tpm2-with-pin=yes --tpm2-pcrs=7+15:sha256=($PCR15_INITIAL)"
    if not ($header | str contains systemd-tpm2) {
        print $"note: luks: no TPM2 seal enrolled, for a measured-boot pin unlock: sudo ($enroll) /dev/($part)"
    } else if ($header =~ 'tpm2-pin:\s+false') {
        print ("note: luks: a TPM2 seal without a pin unlocks any boot, replace it: "
            + $"sudo ($enroll) --wipe-slot=tpm2 /dev/($part)")
    }
    print "luks: header backup, after every keyslot change: configs/base/boot/luks/header-backup.nu (as the admin)"
}

export def configure []: nothing -> nothing {
    let root = root-backing
    crypttab-write $root
    if ("/etc/mkinitcpio.conf" | path exists) { hook-place }
    if $root != null { root-unlock $root }
}
