#!/bin/env bash

set -ex

sudo systemctl enable avahi-daemon.service
sudo systemctl enable cronie.service
sudo systemctl enable cups
sudo systemctl enable firewalld.service
sudo systemctl enable ly.service
sudo systemctl enable ossec-server.target
