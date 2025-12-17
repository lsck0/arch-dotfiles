#!/usr/bin/env bash

set -ex

sudo waydroid init

sudo systemctl enable waydroid-container.service
