#!/usr/bin/env bash

set -ex

# create an initial mirrorlist
ghostmirror \
    -l ./mirrorlist \
    -c Germany,France,Switzerland,Austria,Poland,Denmark,Netherlands \
    -L 30 \
    -Po -S state,outofdate,morerecent,ping

# link the mirrorlist over
sudo ln -sf ${PWD}/mirrorlist /etc/pacman.d/mirrorlist

# fix permissions
sudo touch /etc/pacman.d/mirrorlist.gm.bak
sudo chown $USER:$USER /etc/pacman.d/mirrorlist
sudo chown $USER:$USER /etc/pacman.d/mirrorlist.gm.bak

# install the units by hand rather than letting `ghostmirror -D` manage them
install -Dm644 ./ghostmirror.service ~/.config/systemd/user/ghostmirror.service
install -Dm644 ./ghostmirror.timer ~/.config/systemd/user/ghostmirror.timer

# the weekly run only re-ranks the mirrors it already has, so rebuild the pool
# from upstream monthly to pick up new mirrors
install -Dm644 ./ghostmirror-refresh.service ~/.config/systemd/user/ghostmirror-refresh.service
install -Dm644 ./ghostmirror-refresh.timer ~/.config/systemd/user/ghostmirror-refresh.timer

systemctl --user daemon-reload
systemctl --user enable --now ghostmirror.timer
systemctl --user enable --now ghostmirror-refresh.timer
