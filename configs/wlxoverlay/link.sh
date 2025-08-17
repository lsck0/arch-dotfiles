#!/bin/env bash

set -ex

mkdir -p ${HOME}/.config/wlxoverlay/wayvr.conf.d/

ln -sf ${PWD}/dashboard.yaml ${HOME}/.config/wlxoverlay/wayvr.conf.d/dashboard.yaml
