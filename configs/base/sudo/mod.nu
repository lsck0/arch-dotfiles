use module.nu *

export const meta = {packages: {pacman: [sudo]}}

const DROPINS = [05-timestamp 10-wheel]

export def system [cfg: record] {
    # validated first, a broken drop-in locks every admin out
    for d in $DROPINS { if (^visudo -cf $d | complete).exit_code != 0 { error make {msg: $"sudo: ($d) does not parse"} } }
    $DROPINS | each {|d| file-copy $d $"/etc/sudoers.d/($d)" --mode 440 }
}
