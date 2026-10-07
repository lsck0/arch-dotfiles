#!/usr/bin/env bash

# lactd idles on its socket and changes nothing until a setting is applied in the gui
systemctl enable --now lactd.service
