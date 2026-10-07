#!/usr/bin/env bash

desktop_override gparted.desktop 's|^Exec=.*gparted.*|Exec=pkexec /usr/bin/gparted %f|'
