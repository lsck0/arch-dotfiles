#!/usr/bin/env bash

install -m755 split-lock-mitigate /usr/local/bin/split-lock-mitigate

# the hook stops vllm/ollama to free vram and relaxes split lock mitigation; polkit lets it do both unprompted
install -Dm644 49-gamemode-services.rules /etc/polkit-1/rules.d/49-gamemode-services.rules

# polkit lets the gamemode group set cpu governor and gpu performance level without a prompt
group_add_admins gamemode
