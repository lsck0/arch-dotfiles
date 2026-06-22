#!/usr/bin/env bash

set -ex

/usr/bin/protonup -y

ln -sf ~/.steam/root/compatibilitytools.d ~/.steam/steam/compatibilitytools.d
