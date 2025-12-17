#!/usr/bin/env bash

# remove all stopped containers, dangling images, and unused networks older than 7 days
docker system prune -af  --filter "until=$((7*24))h"
