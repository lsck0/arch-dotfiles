#!/usr/bin/env bash

set -ex

systemctl --user enable opentabletdriver
systemctl --user enable pipewire-pulse.service
systemctl --user enable pipewire-pulse.socket
systemctl --user enable ssh-agent.service
