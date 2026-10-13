#!/usr/bin/env bash

# copied, not linked: pid1 loads drop-ins before /home mounts
# as the last command an unchanged drop-in's false would fail the module
if dropin_install ollama.service keep-alive.conf hardening.conf; then systemctl try-restart ollama.service; fi
