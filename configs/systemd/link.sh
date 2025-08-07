#!/bin/env bash

set -ex

sudo systemctl enable cronie.service
sudo systemctl enable cups
sudo systemctl enable docker.service
sudo systemctl enable firewalld.service
sudo systemctl enable ly.service
sudo systemctl enable nix-daemon
sudo systemctl enable ollama.service
sudo systemctl enable ossec-server.target
sudo systemctl enable sshd
sudo systemctl enable tlp.service
