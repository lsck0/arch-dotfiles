#!/bin/bash

set -xe

CWD=$(pwd)

cd ~/code/qmk_firmware/
qmk compile -e CONVERT_TO=promicro_rp2040 -kb sofle_choc -km luca_sofle_choc
mv ~/code/qmk_firmware/.build/sofle_choc_luca_sofle_choc_promicro_rp2040.uf2 ~/code/arch-dotfiles/keyboard/sofle_choc.uf2

cd $CWD
