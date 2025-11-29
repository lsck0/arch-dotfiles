#!/bin/env bash

set -ex

# create an initial mirrorlist
ghostmirror -c Germany,France,Switzerland,Austria,Poland,Denmark,Netherlands -l ./mirrorlist -L 30 \
    -Po -S state,outofdate,morerecent,ping

# link the mirrorlist over
sudo ln -sf ${PWD}/mirrorlist /etc/pacman.d/mirrorlist

# fix permissions
sudo touch /etc/pacman.d/mirrorlist.gm.bak
sudo chown $USER:$USER /etc/pacman.d/mirrorlist
sudo chown $USER:$USER /etc/pacman.d/mirrorlist.gm.bak

# have ghostmirror linger and periodically sort the mirrorlist
ghostmirror -DPo -mul /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist \
    -s light -S state,outofdate,morerecent,estimated,speed
