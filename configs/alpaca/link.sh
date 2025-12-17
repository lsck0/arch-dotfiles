#!/usr/bin/env bash

set -ex

sudo systemctl enable ollama.service

flatpak install flathub com.jeffser.Alpaca -y
