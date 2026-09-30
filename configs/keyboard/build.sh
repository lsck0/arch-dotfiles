#!/usr/bin/env bash
cd "$(dirname "$(readlink -f "$0")")" || exit 1

set -ex

QMK=qmk_firmware
KEYMAP=luca_sofle_choc

git submodule update --init --depth 1 "$QMK"
git -C "$QMK" submodule update --init --recursive --depth 1
# the keymap lives here, qmk expects it inside its tree (the submodule ignores untracked files)
ln -sfn "${PWD}/sofle_choc" "$QMK/keyboards/sofle_choc/keymaps/$KEYMAP"
QMK_HOME="${PWD}/$QMK" qmk compile -e CONVERT_TO=promicro_rp2040 -e UF2=yes -kb sofle_choc -km "$KEYMAP"
mv "$QMK/.build/sofle_choc_${KEYMAP}_promicro_rp2040.uf2" sofle_choc.uf2
