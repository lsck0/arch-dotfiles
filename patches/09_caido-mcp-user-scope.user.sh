#!/usr/bin/env bash
# drop the user-scope caido mcp server that programming/claude/link.sh used to register; it belongs at project scope in the pentest repos

set -euo pipefail

command -v claude >/dev/null || exit 0
claude mcp remove caido -s user >/dev/null 2>&1 || true
