# trmnl-claude

Claude Code usage on the TRMNL e-ink display.

`claude_trmnl.py` and `template-*.html` are vendored from
<https://github.com/emaspa/trmnl-claude> at commit
`37be9a7e6c6ed47a9406cc22ae2f10d795f7d744`. To update, refetch both at a new
commit and record the SHA here.

The templates are not uploaded; paste each into the plugin's markup editor,
one per layout.

## Setup

The plugin UUID is a write token, so it lives in the private secrets
submodule. `link.sh` skips the install when the file is missing.

```
# configs/base/secrets/trmnl-claude.env
TRMNL_PLUGIN_UUID=...
```

## Operating

```bash
./run.sh --dry-run     # print the payload, post nothing
./run.sh               # post once
./changed.sh           # exit 0 when the timer would post (claude activity or stale data)
systemctl --user status trmnl-claude.timer
journalctl --user -u trmnl-claude -n 20
```
