#!/usr/bin/env bash

# models are pulled lazily on first use, never here: keeps config.sh off the GB download path
link_commands ollama-ensure-models.sh
