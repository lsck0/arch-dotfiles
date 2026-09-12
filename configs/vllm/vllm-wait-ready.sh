#!/usr/bin/env bash

set -uo pipefail

BACKEND_URL="http://127.0.0.1:8001/v1/models"
TIMEOUT_S=600

systemctl start vllm.service

deadline=$((SECONDS + TIMEOUT_S))
while (( SECONDS < deadline )); do
    curl -sf -o /dev/null "$BACKEND_URL" && exit 0
    sleep 2
done

exit 1
