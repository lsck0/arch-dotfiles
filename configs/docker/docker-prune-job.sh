#!/usr/bin/env bash

docker system prune -af --filter "until=$((7 * 24))h"
