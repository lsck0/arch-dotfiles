#!/bin/env bash

set -ex

sudo ln -sf ${PWD}/grub /etc/default/grub

sudo update-grub
