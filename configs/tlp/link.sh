#!/usr/bin/env bash

set -ex

sudo systemctl enable tlp.service

sudo ln -sf ${PWD}/tlp.conf /etc/tlp.conf
