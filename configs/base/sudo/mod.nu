use module.nu *

export const meta = {packages: {pacman: [sudo]}}

# validated first, a broken drop-in locks every admin out; sudoers.d needs a root:root 0440 copy, not a link
export def system [cfg: record] {
    if (^visudo -cf 10-wheel | complete).exit_code != 0 { error make {msg: "sudo: 10-wheel does not parse"} }
    file-copy 10-wheel /etc/sudoers.d/10-wheel --mode 440
}
