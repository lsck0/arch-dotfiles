#!/usr/bin/env bash

set -ex

sudo systemctl enable --now ollama.service

ollama pull gpt-oss:20b
