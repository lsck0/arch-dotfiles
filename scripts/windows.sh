#!/bin/bash
# reboot into w*ndows

sudo efibootmgr --bootnext \
    $(sudo efibootmgr -v | awk 'match($0, /^Boot(.*)\* Windows/, ary) { print ary[1] }')

sudo reboot
