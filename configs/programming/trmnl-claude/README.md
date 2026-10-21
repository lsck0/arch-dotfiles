# trmnl-claude

Claude Code usage on the TRMNL e-ink display.

`trmnl-claude.nu` is a port of `claude_trmnl.py` from <https://github.com/emaspa/trmnl-claude> at commit
`37be9a7e6c6ed47a9406cc22ae2f10d795f7d744`, reading the limits from the API's rate-limit headers only (no `/usage`
TUI scrape, no fleet: one `poster` machine per panel). `template-*.html` are vendored from the same commit.

The templates are not uploaded; paste each into the plugin's markup editor, one per layout.

## Setup

The plugin UUID is a write token, so it lives in the private secrets
submodule. `mod.nu` skips the install when the file is missing or the machine is not the `poster`.

```
# configs/secrets/keys/trmnl-claude.env
TRMNL_PLUGIN_UUID=...
```

## Operating

```bash
./trmnl-claude.nu --dry-run   # print the payload, post nothing
./trmnl-claude.nu             # post once
./trmnl-claude.nu changed     # exit 0 when the timer would post (claude activity or stale data)
systemctl --user status trmnl-claude.timer
journalctl --user -u trmnl-claude -n 20
```
