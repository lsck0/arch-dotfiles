#!/usr/bin/env -S nu --no-config-file

const HERE = path self | path expand | path dirname
const QMK = "qmk_firmware"
const KEYBOARD = "sofle_choc"
const KEYMAP = "luca_sofle_choc"
const CONVERT_TO = "promicro_rp2040"

def main []: nothing -> nothing {
    cd $HERE
    ^git submodule update --init --depth 1 $QMK
    ^git -C $QMK submodule update --init --recursive --depth 1
    # the keymap lives here, qmk expects it inside its tree (the submodule ignores untracked files)
    ^ln -sfn ($HERE | path join $KEYBOARD) ($QMK | path join keyboards $KEYBOARD keymaps $KEYMAP)
    with-env {QMK_HOME: ($HERE | path join $QMK)} {
        ^qmk compile -e $"CONVERT_TO=($CONVERT_TO)" -e UF2=yes -kb $KEYBOARD -km $KEYMAP
    }
    mv --force ($QMK | path join .build $"($KEYBOARD)_($KEYMAP)_($CONVERT_TO).uf2") $"($KEYBOARD).uf2"
}
