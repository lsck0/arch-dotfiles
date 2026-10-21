#!/usr/bin/env -S nu --no-config-file

const SIZE_DEFAULT = "1G"

def container []: nothing -> path { $env.VAULT_HC? | default ($nu.home-dir | path join sync vault.hc) }
def mountpoint []: nothing -> path { $env.VAULT_MOUNT? | default ($nu.home-dir | path join vault) }

def main []: nothing -> nothing {
    print --stderr $"usage: veracrypt-vault create [size]|mount|umount|dismount|status
  create [size]  create (container) \(default ($SIZE_DEFAULT)\), prompts for password
  mount          mount (container) at (mountpoint), prompts for password
  umount         dismount (mountpoint) \(alias: dismount\)
  status         list mounted VeraCrypt volumes"
    exit 2
}

def "main create" [size?: string]: nothing -> nothing {
    if (container | path exists) {
        print --stderr $"refusing to create: (container) already exists"
        exit 1
    }
    let size = $size | default ($env.VAULT_SIZE? | default $SIZE_DEFAULT)
    (^veracrypt --text --create (container) $"--size=($size)" --encryption=AES --hash=SHA-512 --filesystem=ext4
        --volume-type=normal --pim=0 --keyfiles= --random-source=/dev/urandom)
    print --stderr $"created (container) \(($size)\); mount it with: veracrypt-vault mount"
}

def "main mount" []: nothing -> nothing {
    mkdir (mountpoint)
    ^veracrypt --text --mount (container) (mountpoint) --pim=0 --keyfiles= --protect-hidden=no
    print --stderr $"mounted at (mountpoint)"
}

def "main umount" []: nothing -> nothing {
    ^veracrypt --text --dismount (mountpoint)
    print --stderr $"dismounted (mountpoint)"
}

def "main dismount" []: nothing -> nothing { main umount }

# List the mounted volumes; nothing mounted is a state, not the error veracrypt exits 1 with.
def "main status" []: nothing -> nothing {
    let listed = do { ^veracrypt --text --list } | complete
    let out = $listed.stdout + $listed.stderr | str trim
    if $listed.exit_code == 0 {
        print $out
    } else if ($out | str contains "No volumes mounted") {
        print "no volumes mounted"
    } else {
        print --stderr $out
        exit 1
    }
}
