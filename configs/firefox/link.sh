#!/usr/bin/env bash

set -ex

# fix pywalfox not seeing configs
ln -sfn ${HOME}/.config/mozilla/firefox ${HOME}/.config/firefox
