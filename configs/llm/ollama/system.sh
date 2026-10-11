#!/usr/bin/env bash

# copied, not linked: pid1 loads drop-ins before /home mounts
changed=0
file_update keep-alive.conf /etc/systemd/system/ollama.service.d/keep-alive.conf && changed=1
file_update hardening.conf /etc/systemd/system/ollama.service.d/hardening.conf && changed=1
if ((changed)); then
    systemctl daemon-reload
    systemctl try-restart ollama.service
fi
