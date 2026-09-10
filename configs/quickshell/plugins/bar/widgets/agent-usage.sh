#!/usr/bin/env bash
# Local Claude Code token usage for today, summed across all session
# transcripts modified today. NOT the same as omarchy-shell's Agents plugin,
# which hits Anthropic's OAuth-protected usage endpoint for actual plan-limit
# percentages (5h session / 7-day weekly window) — that endpoint isn't
# publicly documented and this repo has no reverse-engineered client for it,
# so this only reports what's derivable from local data: token counts, not
# quota percentage.
set -euo pipefail

find "$HOME/.claude/projects" -name "*.jsonl" -newermt "00:00" 2>/dev/null | \
  xargs -r grep -h '"usage"' 2>/dev/null | \
  python3 -c '
import sys, json

input_tokens = 0
output_tokens = 0
cache_tokens = 0

for line in sys.stdin:
    try:
        d = json.loads(line)
    except Exception:
        continue
    usage = d.get("message", {}).get("usage")
    if not usage:
        continue
    input_tokens += usage.get("input_tokens", 0)
    output_tokens += usage.get("output_tokens", 0)
    cache_tokens += usage.get("cache_creation_input_tokens", 0) + usage.get("cache_read_input_tokens", 0)

print(json.dumps({
    "inputTokens": input_tokens,
    "outputTokens": output_tokens,
    "cacheTokens": cache_tokens,
}))
'
