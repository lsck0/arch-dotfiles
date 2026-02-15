#!/usr/bin/env bash

set -xe

pushd ~/code/qmk_firmware/
qmk compile -e CONVERT_TO=promicro_rp2040 -e UF2=yes -kb sofle_choc -km luca_sofle_choc
mv ~/code/qmk_firmware/.build/sofle_choc_luca_sofle_choc_promicro_rp2040.uf2 ~/code/arch-dotfiles/keyboard/sofle_choc.uf2
popd
