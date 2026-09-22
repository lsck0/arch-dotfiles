# trmnl-claude

Claude Code usage on the TRMNL e-ink display.

Upstream: <https://github.com/emaspa/trmnl-claude>, vendored at commit
`37be9a7e6c6ed47a9406cc22ae2f10d795f7d744`. `claude_trmnl.py` and the four
`template-*.html` files are copies, not a submodule, so an upstream change
never lands here unnoticed. To update, refetch both at a new commit and record
the SHA in this file.

The script is stdlib-only. It reads `~/.claude/` for token counts and asks the
Anthropic API for the rate-limit headers that carry the session and weekly
percentages, then POSTs merge variables to the plugin webhook. It never uploads
markup: the templates have to be pasted into the plugin's markup editor, one
per layout.

The unit runs with no flags. The session and weekly percentages come from the
API's rate-limit headers, which cost one `max_tokens: 1` request and need no
extra package; `--no-scrape` would drop those bars entirely, and the PTY
fallback that reads them out of the `/usage` TUI is the one that needs
`pexpect`.

## Layout

| file | what |
|---|---|
| `claude_trmnl.py` | upstream script, vendored |
| `template-*.html` | upstream Liquid templates, one per TRMNL layout |
| `run.sh` | loads the UUID from the secrets submodule, runs the script |
| `trmnl-claude.{service,timer}` | posts every 15 minutes |
| `link.sh` | symlinks the units and enables the timer |

## The UUID is a secret

The plugin UUID is a write token: anyone holding it can post anything to the
display. arch-dotfiles is public, so it lives in the private `configs/secrets`
submodule as `trmnl-claude.env` and reaches the script only through the
environment. `link.sh` skips the install when that file is missing rather than
enabling a timer that fails every 15 minutes.

```
# configs/secrets/trmnl-claude.env
TRMNL_PLUGIN_UUID=...
```

## Operating

```bash
./run.sh --dry-run     # print the payload, post nothing
./run.sh               # post once
systemctl --user status trmnl-claude.timer
journalctl --user -u trmnl-claude -n 20
```
