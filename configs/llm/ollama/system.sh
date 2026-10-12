#!/usr/bin/env bash

# copied, not linked: pid1 loads drop-ins before /home mounts
dropin_install ollama.service keep-alive.conf hardening.conf && systemctl try-restart ollama.service
