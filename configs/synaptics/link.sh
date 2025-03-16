#!/bin/env bash

set -ex

sudo mkdir -p /etc/X11/xorg.conf.d
sudo ln -sf ${PWD}/config /etc/X11/xorg.conf.d/70-synaptics.conf
