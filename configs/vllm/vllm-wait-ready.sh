#!/usr/bin/env bash

set -uo pipefail

BACKEND_URL="http://127.0.0.1:8001/v1/models"
TIMEOUT_S=600

# log the client that connected to :8000 and triggered this on-demand start (journalctl -u vllm-proxy -g vllm-trigger)
ss -Htnp '( sport = :8000 or dport = :8000 )' 2>/dev/null | grep -v systemd-socket-proxyd | sed 's/^/vllm-trigger: /' >&2 || true

systemctl start vllm.service

deadline=$((SECONDS + TIMEOUT_S))
while (( SECONDS < deadline )); do
    curl -sf -o /dev/null "$BACKEND_URL" && exit 0
    sleep 2
done

exit 1
