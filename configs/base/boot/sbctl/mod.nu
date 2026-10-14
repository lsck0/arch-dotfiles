use module.nu *

export const meta = {packages: {native: [sbctl]}, volatile: true}

const PK_VAR = "/sys/firmware/efi/efivars/PK-8be4df61-93ca-11d2-aa0d-00e098032b8c"
const PK_CERT = "/var/lib/sbctl/keys/PK/PK.pem"
const EVENT_LOG = "/sys/kernel/security/tpm0/binary_bios_measurements"
# sbctl verify only walks the esp
const BOOT_FILES = [
    /boot/EFI/BOOT/BOOTX64.EFI /boot/EFI/systemd/systemd-bootx64.efi
    /boot/efi/EFI/BOOT/BOOTX64.EFI /boot/efi/EFI/systemd/systemd-bootx64.efi
]

export def system [cfg: record] {
    if not ("/sys/firmware/efi" | path exists) { return [] }
    step secure-boot (if (platform-has secure_boot_own_keys) { "own" } else { "microsoft" })
}

def status-has [field: string]: nothing -> bool {
    ^sbctl status | str contains --ignore-case $field
}

def enabled [field: string]: nothing -> bool {
    ^sbctl status | lines | any { $in =~ $'($field):\s+(\S+\s+)?Enabled' }
}

# the plain kernels stay unsigned: a type #1 entry on the unverified esp could boot a signed one with any cmdline
def sign-unsigned []: nothing -> nothing {
    let listed = ^sbctl verify | lines | parse --regex '^[^/]*(?<path>/.*) is not signed$' | get path
        | where {|p| not ($p | str starts-with /boot/vmlinuz-) }
    let extra = $BOOT_FILES | append (glob /boot/EFI/Linux/*.efi) | where {|f|
        ($f | path exists) and $f not-in $listed and not (^sbctl verify $f | str contains "is signed")
    }
    for file in ($listed ++ $extra) {
        print $"sbctl: signing ($file)"
        ^sbctl sign -s $file
    }
    ^sbctl sign-all
}

# some firmware (ami) clears SetupMode only at the next reset: our PK certificate inside the PK variable is the proof
def pk-enrolled []: nothing -> bool {
    if not ($PK_VAR | path exists) { return false }
    let cert = ^openssl x509 -in $PK_CERT -outform DER | into binary | encode hex
    $cert != "" and (open --raw $PK_VAR | into binary | encode hex | str contains $cert)
}

def enroll [keys: string]: nothing -> nothing {
    if $keys == "own" and ($EVENT_LOG | path exists) {
        print "sbctl: enrolling own keys plus the TPM event log's option rom hashes, no Microsoft keys"
        let out = ^sbctl enroll-keys -t | complete
        # a machine without option roms has no hashes and -t refuses; nothing then needs microsoft's ca
        if $out.exit_code != 0 {
            print $out.stdout $out.stderr
            if ($out.stdout + $out.stderr | str contains "could not find any OpROM entries") { ^sbctl enroll-keys }
        }
    } else {
        if $keys == "own" {
            # without an event log, dropping microsoft's ca could brick a machine whose option rom needs it
            print ("note: sbctl: own keys wanted but no TPM event log to read option rom hashes from, "
                + "Microsoft's CA stays in db")
        }
        ^sbctl enroll-keys -m
    }
}

export def secure-boot [keys: string]: nothing -> nothing {
    if (enabled "Secure Boot") {
        sign-unsigned
        return
    }
    if not (enabled "Setup Mode") {
        print ("note: sbctl: firmware not in Setup Mode and Secure Boot not enabled; "
            + "enable Setup Mode, then rerun dot apply")
        return
    }
    if not (status-has "Owner GUID") { ^sbctl create-keys }
    sign-unsigned
    # efivarfs marks them immutable and enroll-keys then never writes PK; the firmware still guards them
    for var in (glob /sys/firmware/efi/efivars/{PK,KEK,db,dbx}-*) { ^chattr -i $var }
    enroll $keys
    if not (pk-enrolled) {
        error make {
            msg: "sbctl: enroll-keys ran but our PK is not in the PK variable (enroll failed or efivars locked)"
        }
    }
    print ("note: sbctl: keys enrolled and boot files signed. Check 'sbctl verify', enable Secure Boot in firmware, "
        + "reboot, rerun dot apply")
}
