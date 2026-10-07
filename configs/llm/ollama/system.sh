#!/usr/bin/env bash

# copied, not linked: pid1 loads drop-ins before /home mounts
if file_update keep-alive.conf /etc/systemd/system/ollama.service.d/keep-alive.conf; then
    systemctl daemon-reload
    systemctl try-restart ollama.service
fi
